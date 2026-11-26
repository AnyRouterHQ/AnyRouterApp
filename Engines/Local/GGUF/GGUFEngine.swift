import Foundation

/// Keeps one model loaded. Loading is slow (seconds), so a second chat with the same model reuses it.
/// The cache key is the file's path and the time it was installed, so a download to the same path replaces the weights.
actor LlamaModelCache {
    private struct Key: Equatable {
        var path: String
        var installedAt: Date?
    }

    private var current: (id: String, key: Key, model: LlamaModel)?
    /// A load in progress. A second request for the same file joins it instead of loading the weights twice.
    private var loading: (key: Key, task: Task<LlamaModel, Error>)?
    private let telemetry: any Telemetry

    init(telemetry: any Telemetry = NoopTelemetry()) {
        self.telemetry = telemetry
    }

    /// Id of the loaded model, nil when none is.
    var loadedID: String? { current?.id }

    func model(at path: String, id: String, installedAt: Date? = nil) async throws -> LlamaModel {
        let key = Key(path: path, installedAt: installedAt)
        if let current, current.key == key { return current.model }
        if let loading, loading.key == key { return try await loading.task.value }
        current = nil // free the old weights before the new ones load
        let started = ContinuousClock.now
        let task = Task.detached(priority: .userInitiated) { try LlamaModel(path: path) }
        loading = (key, task)
        do {
            let loaded = try await task.value
            if loading?.key == key {
                loading = nil
                current = (id, key, loaded)
                telemetry.track(.engineLoadMs(TelemetryEvent.milliseconds(ContinuousClock.now - started), source: .gguf))
            }
            return loaded
        } catch {
            if loading?.key == key { loading = nil }
            throw error
        }
    }

    func unload() {
        current = nil
    }

    /// Frees the weights only when they belong to this model (it was deleted or replaced).
    func unload(ifID id: String) {
        if current?.id == id { current = nil }
    }
}

/// One generation at a time: two contexts on a phone would double the KV-cache memory.
actor GenerationGate {
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        if !busy {
            busy = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    /// Takes the gate only when no generation holds it and none waits. For background work that must never delay a chat.
    func tryAcquire() -> Bool {
        guard !busy else { return false }
        busy = true
        return true
    }

    func release() {
        if waiters.isEmpty {
            busy = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}

/// Chats with downloaded GGUF models through llama.cpp.
final class GGUFEngine: ChatEngine {
    let source: ModelSource = .gguf

    private let storage: LocalModelStorage
    private let catalog: CatalogService
    private let cache: LlamaModelCache
    /// One generation at a time. Internal so tests can hold it.
    let gate = GenerationGate()

    init(storage: LocalModelStorage = LocalModelStorage(), catalog: CatalogService = CatalogService(),
         telemetry: any Telemetry = NoopTelemetry()) {
        self.storage = storage
        self.catalog = catalog
        self.cache = LlamaModelCache(telemetry: telemetry)
    }

    func availableModels() async throws -> [ModelDescriptor] {
        let entries = (try? await catalog.entries()) ?? []
        return LocalModelDescriptors.installed(format: .gguf, storage: storage, catalog: entries)
    }

    /// Frees the loaded weights, e.g. on a memory warning.
    func unload() async {
        await cache.unload()
    }

    /// Id of the model whose weights are in memory now.
    func loadedModelID() async -> String? {
        await cache.loadedID
    }

    /// Frees the weights when they belong to `modelID`, for example because it was deleted.
    func unload(modelID: String) async {
        await cache.unload(ifID: modelID)
    }

    /// For the smoke report: which formatter writes this model's prompt, what it writes for "hi", and which of the given
    /// special tokens stop generation. Loads the model if it is not loaded. Nil when the model is not installed.
    func promptReport(model: ModelDescriptor, stopTexts: [String]) async -> (path: String, prompt: String, stops: String)? {
        guard let manifest = storage.readManifest(entryID: model.id), let file = manifest.files.first,
              let llama = try? await cache.model(
                  at: storage.fileURL(forEntryID: model.id, path: file.path).path, id: model.id, installedAt: manifest.completedAt)
        else { return nil }
        let formatted = llama.format([PromptMessage(role: "user", content: "hi")])
        return (formatted.path.rawValue, formatted.text, llama.stopReport(for: stopTexts))
    }

    /// Loads the weights ahead of the first message. No context is created, so it costs memory but no compute.
    /// Does nothing for a model that is not installed, and nothing while a generation is running: a warm-up never
    /// competes with a chat. A send that arrives during the warm-up waits at the gate, then finds the weights loaded.
    func warm(model: ModelDescriptor) async {
        guard let manifest = storage.readManifest(entryID: model.id), let file = manifest.files.first else { return }
        guard await gate.tryAcquire() else { return }
        let path = storage.fileURL(forEntryID: model.id, path: file.path).path
        _ = try? await cache.model(at: path, id: model.id, installedAt: manifest.completedAt)
        await gate.release()
    }

    func stream(model: ModelDescriptor, messages: [ChatMessage], params: GenerationParams)
        -> AsyncThrowingStream<ChatDelta, Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached(priority: .userInitiated) { [storage, cache, gate] in
                await gate.acquire()
                do {
                    guard let manifest = storage.readManifest(entryID: model.id), let file = manifest.files.first else {
                        throw GGUFError.modelNotInstalled(model.id)
                    }
                    let path = storage.fileURL(forEntryID: model.id, path: file.path).path
                    let llama = try await cache.model(at: path, id: model.id, installedAt: manifest.completedAt)
                    let result = try Self.run(llama, messages: messages, params: params) { continuation.yield(.text($0)) }
                    continuation.yield(.usage(prompt: result.promptTokens, completion: result.completionTokens))
                    continuation.yield(.done(finishReason: result.finishReason))
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
                await gate.release()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func run(
        _ llama: LlamaModel, messages: [ChatMessage], params: GenerationParams, emit: (String) -> Void
    ) throws -> LlamaResult {
        let contextSize = llama.contextSize
        // Leave room for the answer, then drop the oldest turns that do not fit.
        let reserve = min(params.maxTokens ?? 1024, contextSize / 2)
        let budget = contextSize - reserve
        let all = PromptBuilder.promptMessages(from: messages, systemPrompt: params.systemPrompt)
        let fitted = try PromptBuilder.trimmed(all) { try llama.tokenize(llama.formatPrompt($0)).count <= budget }
        guard let fitted else {
            let needed = try llama.tokenize(llama.formatPrompt(all)).count
            throw GGUFError.promptTooLong(tokens: needed, limit: budget)
        }
        let tokens = try llama.tokenize(llama.formatPrompt(fitted))
        return try llama.generate(
            promptTokens: tokens, params: params, isCancelled: { Task.isCancelled }, emit: emit)
    }
}
