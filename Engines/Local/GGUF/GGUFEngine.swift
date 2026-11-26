import Foundation

/// Keeps one model loaded. Loading is slow (seconds), so a second chat with the same model reuses it.
actor LlamaModelCache {
    private var current: (path: String, model: LlamaModel)?

    func model(at path: String) async throws -> LlamaModel {
        if let current, current.path == path { return current.model }
        current = nil // free the old weights before the new ones load
        let loaded = try await Task.detached(priority: .userInitiated) { try LlamaModel(path: path) }.value
        current = (path, loaded)
        return loaded
    }

    func unload() {
        current = nil
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
    private let cache = LlamaModelCache()
    private let gate = GenerationGate()

    init(storage: LocalModelStorage = LocalModelStorage(), catalog: CatalogService = CatalogService()) {
        self.storage = storage
        self.catalog = catalog
    }

    func availableModels() async throws -> [ModelDescriptor] {
        let entries = (try? await catalog.entries()) ?? []
        return LocalModelDescriptors.installed(format: .gguf, storage: storage, catalog: entries)
    }

    /// Frees the loaded weights, e.g. on a memory warning.
    func unload() async {
        await cache.unload()
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
                    let llama = try await cache.model(at: path)
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
