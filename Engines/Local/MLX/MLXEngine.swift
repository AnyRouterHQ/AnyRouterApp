import Foundation
import MLXLLM
import MLXLMCommon

/// Chats with downloaded MLX models through mlx-swift-lm. Needs a real GPU: unavailable in the Simulator.
final class MLXEngine: ChatEngine {
    let source: ModelSource = .mlx

    /// Rolling KV cache size. Bounds memory on a phone; older tokens are dropped from attention beyond it.
    static let maxKVSize = 4096

    private let storage: LocalModelStorage
    private let catalog: CatalogService
    private let residency: LocalResidency

    /// Pass one `LocalResidency` to every local engine of the app. Without it the engine keeps its own.
    init(storage: LocalModelStorage = LocalModelStorage(), catalog: CatalogService = CatalogService(),
         telemetry: any Telemetry = NoopTelemetry(), residency: LocalResidency? = nil) {
        self.storage = storage
        self.catalog = catalog
        self.residency = residency ?? LocalResidency(telemetry: telemetry)
    }

    static var availability: MLXAvailability {
        #if targetEnvironment(simulator)
        return .unavailable("MLX models need an iPhone or iPad with a GPU. Use a GGUF model in the Simulator.")
        #else
        return .available
        #endif
    }

    func availableModels() async throws -> [ModelDescriptor] {
        let entries = (try? await catalog.entries()) ?? []
        return LocalModelDescriptors.installed(format: .mlx, storage: storage, catalog: entries)
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

    func stream(model: ModelDescriptor, messages: [ChatMessage], params: GenerationParams)
        -> AsyncThrowingStream<ChatDelta, Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached(priority: .userInitiated) { [storage, residency] in
                await residency.gate.acquire()
                do {
                    // Stop pressed while this waited its turn: do not load a model for a reply nobody reads.
                    try Task.checkCancellation()
                    if case .unavailable(let reason) = Self.availability { throw MLXError.unavailable(reason) }
                    guard storage.isInstalled(entryID: model.id) else { throw MLXError.modelNotInstalled(model.id) }
                    let conversation = try MLXConversation.split(messages: messages, systemPrompt: params.systemPrompt)
                    let directory = storage.directory(forEntryID: model.id)
                    let container = try await residency.models.weights(
                        ModelContainer.self, at: directory.path, id: model.id,
                        installedAt: storage.readManifest(entryID: model.id)?.completedAt, source: .mlx
                    ) { try await loadModelContainer(from: directory, using: TransformersTokenizerLoader()) }
                    try await Self.generate(container, conversation: conversation, params: params, into: continuation)
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

    private static func generate(
        _ container: ModelContainer, conversation: MLXConversation, params: GenerationParams,
        into continuation: AsyncThrowingStream<ChatDelta, Error>.Continuation
    ) async throws {
        let parameters = GenerateParameters(
            maxTokens: params.maxTokens, maxKVSize: maxKVSize,
            temperature: Float(params.temperature), topP: Float(params.topP))
        let history = conversation.history.map { turn in
            Chat.Message(role: turn.role == "assistant" ? .assistant : .user, content: turn.content)
        }
        let session = ChatSession(
            container, instructions: conversation.instructions, history: history, generateParameters: parameters)

        var usage: (prompt: Int, completion: Int)?
        var finishReason = "stop"
        for try await generation in session.streamDetails(to: conversation.prompt) {
            switch generation {
            case .chunk(let text):
                continuation.yield(.text(text))
            case .info(let info):
                usage = (info.promptTokenCount, info.generationTokenCount)
                if case .length = info.stopReason { finishReason = "length" }
            default:
                break // reasoning, tool calls and steering are not part of v1 chat
            }
        }
        // The consumer left: the stream above ended early, so do not report a normal finish.
        if Task.isCancelled { throw CancellationError() }
        if let usage { continuation.yield(.usage(prompt: usage.prompt, completion: usage.completion)) }
        continuation.yield(.done(finishReason: finishReason))
    }
}
