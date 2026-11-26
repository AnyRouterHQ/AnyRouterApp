import Foundation

/// Chats with downloaded GGUF models through llama.cpp.
final class GGUFEngine: ChatEngine {
    let source: ModelSource = .gguf

    private let storage: LocalModelStorage
    private let catalog: CatalogService
    private let residency: LocalResidency
    /// One generation at a time, shared with the other local engines. Internal so tests can hold it.
    var gate: GenerationGate { residency.gate }

    /// Pass one `LocalResidency` to every local engine of the app. Without it the engine keeps its own.
    init(storage: LocalModelStorage = LocalModelStorage(), catalog: CatalogService = CatalogService(),
         telemetry: any Telemetry = NoopTelemetry(), residency: LocalResidency? = nil) {
        self.storage = storage
        self.catalog = catalog
        self.residency = residency ?? LocalResidency(telemetry: telemetry)
    }

    func availableModels() async throws -> [ModelDescriptor] {
        let entries = (try? await catalog.entries()) ?? []
        return LocalModelDescriptors.installed(format: .gguf, storage: storage, catalog: entries)
    }

    /// Frees the loaded weights, e.g. on a memory warning.
    func unload() async {
        await residency.models.unload()
    }

    /// Id of the model whose weights are in memory now.
    func loadedModelID() async -> String? {
        await residency.models.loadedID
    }

    /// Frees the weights when they belong to `modelID`, for example because it was deleted.
    func unload(modelID: String) async {
        await residency.models.unload(ifID: modelID)
    }

    /// For the smoke report: which formatter writes this model's prompt, what it writes for "hi", and which of the given
    /// special tokens stop generation. Loads the model if it is not loaded. Nil when the model is not installed.
    func promptReport(model: ModelDescriptor, stopTexts: [String]) async -> (path: String, prompt: String, stops: String)? {
        guard let manifest = storage.readManifest(entryID: model.id), let file = manifest.files.first,
              let llama = try? await loadWeights(model.id, file: file.path, installedAt: manifest.completedAt)
        else { return nil }
        let formatted = llama.format([PromptMessage(role: "user", content: "hi")])
        return (formatted.path.rawValue, formatted.text, llama.stopReport(for: stopTexts))
    }

    /// Loads the weights ahead of the first message. No context is created, so it costs memory but no compute.
    /// Does nothing for a model that is not installed, and nothing while a generation is running: a warm-up never
    /// competes with a chat. A send that arrives during the warm-up waits at the gate, then finds the weights loaded.
    func warm(model: ModelDescriptor) async {
        guard let manifest = storage.readManifest(entryID: model.id), let file = manifest.files.first else { return }
        guard await residency.gate.tryAcquire() else { return }
        _ = try? await loadWeights(model.id, file: file.path, installedAt: manifest.completedAt)
        await residency.gate.release()
    }

    /// The loaded weights of an installed model, loading them first when they are not in memory.
    private func loadWeights(_ id: String, file: String, installedAt: Date?) async throws -> LlamaModel {
        let path = storage.fileURL(forEntryID: id, path: file).path
        return try await residency.models.weights(
            LlamaModel.self, at: path, id: id, installedAt: installedAt, source: .gguf
        ) { try LlamaModel(path: path) }
    }

    func stream(model: ModelDescriptor, messages: [ChatMessage], params: GenerationParams)
        -> AsyncThrowingStream<ChatDelta, Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached(priority: .userInitiated) { [self, storage, residency] in
                await residency.gate.acquire()
                do {
                    // Stop pressed while this waited its turn: do not load a model for a reply nobody reads.
                    try Task.checkCancellation()
                    guard let manifest = storage.readManifest(entryID: model.id), let file = manifest.files.first else {
                        throw GGUFError.modelNotInstalled(model.id)
                    }
                    let llama = try await loadWeights(model.id, file: file.path, installedAt: manifest.completedAt)
                    let result = try Self.run(llama, messages: messages, params: params) { continuation.yield(.text($0)) }
                    continuation.yield(.usage(prompt: result.promptTokens, completion: result.completionTokens))
                    continuation.yield(.done(finishReason: result.finishReason))
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
                await residency.gate.release()
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
