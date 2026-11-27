import Foundation
import Synchronization

/// Chats with downloaded GGUF models through llama.cpp.
final class GGUFEngine: ChatEngine {
    let source: ModelSource = .gguf

    private let storage: LocalModelStorage
    private let catalog: CatalogService
    private let residency: LocalResidency
    private let attachments: AttachmentStore
    /// Where each load leaves its steps (Settings › Diagnostics). Nil records nothing.
    private let loadLog: DiagnosticsStore?
    /// A load the warm-up started, by model id: the first reply after it adds its steps to the same record.
    private let warmedTraces = Mutex<[String: ModelLoadRecorder]>([:])
    /// One generation at a time, shared with the other local engines. Internal so tests can hold it.
    var gate: GenerationGate { residency.gate }

    /// Pass one `LocalResidency` to every local engine of the app. Without it the engine keeps its own.
    init(storage: LocalModelStorage = LocalModelStorage(), catalog: CatalogService = CatalogService(),
         telemetry: any Telemetry = NoopTelemetry(), residency: LocalResidency? = nil,
         attachments: AttachmentStore = .shared, loadLog: DiagnosticsStore? = nil) {
        self.storage = storage
        self.attachments = attachments
        self.loadLog = loadLog
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
        let trace = loadLog.map { ModelLoadRecorder(store: $0, model: file.path) }
        _ = try? await loadWeights(model.id, file: file.path, installedAt: manifest.completedAt, trace: trace)
        if let trace, trace.isOpen { warmedTraces.withLock { $0[model.id] = trace } }
        await residency.gate.release()
    }

    /// The loaded weights of an installed model, loading them first when they are not in memory.
    private func loadWeights(
        _ id: String, file: String, installedAt: Date?, trace: ModelLoadRecorder? = nil
    ) async throws -> LlamaModel {
        let path = storage.fileURL(forEntryID: id, path: file).path
        return try await residency.models.weights(
            LlamaModel.self, at: path, id: id, installedAt: installedAt, source: .gguf
        ) {
            trace?.mark(.started)
            do {
                let llama = try LlamaModel(path: path)
                trace?.mark(.mapped, note: llama.loadPlan)
                return llama
            } catch {
                trace?.mark(.failed, note: error.localizedDescription)
                throw error
            }
        }
    }

    func stream(model: ModelDescriptor, messages: [ChatMessage], params: GenerationParams)
        -> AsyncThrowingStream<ChatDelta, Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached(priority: .userInitiated) { [self, storage, residency, attachments] in
                await residency.gate.acquire()
                // Steps of this reply are recorded only when it loaded the weights, or follows the warm-up that did.
                var steps: ModelLoadRecorder?
                do {
                    // Stop pressed while this waited its turn: do not load a model for a reply nobody reads.
                    try Task.checkCancellation()
                    guard let manifest = storage.readManifest(entryID: model.id), let file = manifest.files.first else {
                        throw GGUFError.modelNotInstalled(model.id)
                    }
                    let warmed = warmedTraces.withLock { $0.removeValue(forKey: model.id) }
                    let trace = warmed ?? loadLog.map { ModelLoadRecorder(store: $0, model: file.path) }
                    let llama = try await loadWeights(model.id, file: file.path, installedAt: manifest.completedAt, trace: trace)
                    steps = trace?.isOpen == true ? trace : nil
                    let sampling = (try? await catalog.entries())?.first(where: { $0.id == model.id })?.sampling
                    let tuned = sampling.map { $0.applied(to: params) } ?? params
                    let result: LlamaResult
                    if let images = await imageInput(model: model, manifest: manifest, messages: messages) {
                        result = try Self.runWithImages(
                            llama, messages: messages, params: tuned, sampling: sampling, input: images, store: attachments,
                            trace: steps
                        ) { continuation.yield(.text($0)) }
                    } else {
                        result = try Self.run(llama, messages: messages, params: tuned, sampling: sampling, trace: steps) {
                            continuation.yield(.text($0))
                        }
                    }
                    continuation.yield(.usage(prompt: result.promptTokens, completion: result.completionTokens))
                    continuation.yield(.done(finishReason: result.finishReason))
                    continuation.finish()
                } catch is CancellationError {
                    steps?.mark(.stopped)
                    continuation.finish()
                } catch {
                    if steps?.isOpen == true { steps?.mark(.failed, note: error.localizedDescription) }
                    continuation.finish(throwing: error)
                }
                await residency.gate.release()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// What a message with photos needs from the model's files: the projector, and the image size it reads.
    struct ImageInput: Equatable, Sendable {
        var projectorPath: String
        var side: Int
    }

    /// Set when the last user message has photos and the download holds a projector. Otherwise the photos go in as the text
    /// read from them.
    private func imageInput(model: ModelDescriptor, manifest: InstalledManifest, messages: [ChatMessage]) async -> ImageInput? {
        guard Self.hasImages(messages),
              let projector = manifest.files.first(where: { VisionInput.isProjector(path: $0.path) })
        else { return nil }
        let entry = (try? await catalog.entries())?.first { $0.id == model.id }
        return ImageInput(
            projectorPath: storage.fileURL(forEntryID: model.id, path: projector.path).path,
            side: VisionInput.imageSide(for: entry?.vision))
    }

    /// Whether the last user message carries a photo.
    static func hasImages(_ messages: [ChatMessage]) -> Bool {
        messages.last(where: { $0.role == .user })?.attachments.contains { $0.kind == .image } ?? false
    }

    /// Reads each photo from the store and scales it to the longest side the model reads.
    static func imageData(_ images: [ChatAttachment], side: Int, store: AttachmentStore) throws -> [Data] {
        try images.map { image in
            guard let data = store.data(for: image), let scaled = ImageProcessing.jpeg(from: data, maxSide: side) else {
                throw GGUFError.imageUnreadable
            }
            return scaled
        }
    }

    private static func runWithImages(
        _ llama: LlamaModel, messages: [ChatMessage], params: GenerationParams, sampling: CatalogSampling?, input: ImageInput,
        store: AttachmentStore, trace: ModelLoadRecorder?, emit: (String) -> Void
    ) throws -> LlamaResult {
        let contextSize = llama.contextSize
        let reserve = min(params.maxTokens ?? 1024, contextSize / 2)
        // The photos take their own share of the context: count them on top of the text.
        let built = VisionInput.prompt(from: messages, systemPrompt: params.systemPrompt)
        let photoTokens = built.images.count * VisionInput.tokensPerImage
        let budget = contextSize - reserve
        let fitted = try PromptBuilder.trimmed(built.messages) {
            try llama.tokenize(llama.formatPrompt($0)).count + photoTokens <= budget
        }
        guard let fitted else {
            let needed = try llama.tokenize(llama.formatPrompt(built.messages)).count + photoTokens
            throw GGUFError.promptTooLong(tokens: needed, limit: budget)
        }
        let data = try imageData(built.images, side: input.side, store: store)
        let prepared = try llama.prepareImages(
            text: llama.formatPrompt(fitted), images: data, projectorPath: input.projectorPath)
        return try llama.generate(
            images: prepared, params: params, sampling: sampling, isCancelled: { Task.isCancelled },
            onStep: trace?.onStep, emit: emit)
    }

    private static func run(
        _ llama: LlamaModel, messages: [ChatMessage], params: GenerationParams, sampling: CatalogSampling?,
        trace: ModelLoadRecorder?, emit: (String) -> Void
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
            promptTokens: tokens, params: params, sampling: sampling, isCancelled: { Task.isCancelled },
            onStep: trace?.onStep, emit: emit)
    }
}
