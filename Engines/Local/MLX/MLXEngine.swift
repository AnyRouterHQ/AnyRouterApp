import Foundation
import MLXLLM
import MLXLMCommon

/// Keeps one model loaded. Loading reads the whole snapshot into memory, so a second chat reuses it.
actor MLXModelCache {
    private struct Key: Equatable {
        var directory: URL
        var installedAt: Date?
    }

    private var current: (id: String, key: Key, container: ModelContainer)?
    /// A load in progress. A second request for the same snapshot joins it instead of reading the weights twice.
    private var loading: (key: Key, task: Task<ModelContainer, Error>)?
    private let telemetry: any Telemetry

    init(telemetry: any Telemetry = NoopTelemetry()) {
        self.telemetry = telemetry
    }

    /// Id of the loaded model, nil when none is.
    var loadedID: String? { current?.id }

    func container(at directory: URL, id: String, installedAt: Date? = nil) async throws -> ModelContainer {
        let key = Key(directory: directory, installedAt: installedAt)
        if let current, current.key == key { return current.container }
        if let loading, loading.key == key { return try await loading.task.value }
        current = nil // release the old weights before the new ones load
        let started = ContinuousClock.now
        let task = Task { try await loadModelContainer(from: directory, using: TransformersTokenizerLoader()) }
        loading = (key, task)
        do {
            let loaded = try await task.value
            if loading?.key == key {
                loading = nil
                current = (id, key, loaded)
                telemetry.track(.engineLoadMs(TelemetryEvent.milliseconds(ContinuousClock.now - started), source: .mlx))
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

/// Chats with downloaded MLX models through mlx-swift-lm. Needs a real GPU: unavailable in the Simulator.
final class MLXEngine: ChatEngine {
    let source: ModelSource = .mlx

    /// Rolling KV cache size. Bounds memory on a phone; older tokens are dropped from attention beyond it.
    static let maxKVSize = 4096

    private let storage: LocalModelStorage
    private let catalog: CatalogService
    private let cache: MLXModelCache
    private let gate = GenerationGate()

    init(storage: LocalModelStorage = LocalModelStorage(), catalog: CatalogService = CatalogService(),
         telemetry: any Telemetry = NoopTelemetry()) {
        self.storage = storage
        self.catalog = catalog
        self.cache = MLXModelCache(telemetry: telemetry)
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

    func stream(model: ModelDescriptor, messages: [ChatMessage], params: GenerationParams)
        -> AsyncThrowingStream<ChatDelta, Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached(priority: .userInitiated) { [storage, cache, gate] in
                await gate.acquire()
                do {
                    if case .unavailable(let reason) = Self.availability { throw MLXError.unavailable(reason) }
                    guard storage.isInstalled(entryID: model.id) else { throw MLXError.modelNotInstalled(model.id) }
                    let conversation = try MLXConversation.split(messages: messages, systemPrompt: params.systemPrompt)
                    let container = try await cache.container(
                        at: storage.directory(forEntryID: model.id), id: model.id,
                        installedAt: storage.readManifest(entryID: model.id)?.completedAt)
                    try await Self.generate(container, conversation: conversation, params: params, into: continuation)
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
