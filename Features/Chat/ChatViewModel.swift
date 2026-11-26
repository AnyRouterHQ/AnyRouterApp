import Foundation
import Observation
import SwiftData

/// Send, stream, stop and regenerate for one thread. A new chat has no thread until the first send.
@MainActor @Observable
final class ChatViewModel {
    enum Phase: Equatable { case idle, streaming }

    var input = ""
    private(set) var phase: Phase = .idle
    private(set) var errorMessage: String?
    /// Name of the local model that is loading or reading the prompt, until its first token arrives. Nil otherwise.
    /// The UI shows "Loading <name>…" and stays usable; Stop cancels.
    private(set) var loadingModelName: String?
    private(set) var thread: ThreadRecord?
    /// Bumps when the composer should take focus (after a preset fills it).
    private(set) var focusTick = 0
    /// Per-thread "Enable thinking"; a new chat keeps it here until the first send creates the thread.
    private(set) var thinkingEnabled = false
    private(set) var toolsDisabled = false
    /// Model id saved on this thread. `nil` follows the default for new chats.
    private(set) var preferredModelID: String?
    /// Files and photos waiting under the composer for the next send.
    private(set) var pending: [ChatAttachment] = []
    /// Attachments still being read (images are shrunk, text and OCR are read off the main actor).
    private(set) var ingesting = 0
    /// Pending files that could not be moved into the thread at the last send. They stay pending, marked.
    private(set) var failedAttachmentIDs: Set<UUID> = []
    /// Id of the thread a first send creates, so files moved by a send that failed halfway are found again.
    let draftThreadID = UUID()

    /// Called once when the first send creates the thread.
    @ObservationIgnored var onThreadCreated: (@MainActor (UUID) -> Void)?

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let registry: EngineRegistry
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let models: ModelStore
    @ObservationIgnored private let save: (ModelContext) throws -> Void
    /// Seconds from any steady clock. Injected so timings are testable.
    @ObservationIgnored private let now: () -> TimeInterval
    /// Builds the tools for one request from what the chat holds: its attachments and the user's own words.
    @ObservationIgnored private let toolHost: @MainActor (ToolContext) -> (any ToolHost)?
    @ObservationIgnored let attachmentStore: AttachmentStore
    @ObservationIgnored private var task: Task<Void, Never>?

    init(thread: ThreadRecord?, context: ModelContext, registry: EngineRegistry,
         settings: AppSettings, models: ModelStore,
         toolHost: @escaping @MainActor (ToolContext) -> (any ToolHost)? = { _ in nil },
         attachments: AttachmentStore = .shared,
         save: @escaping (ModelContext) throws -> Void = { try $0.save() },
         now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.save = save
        self.now = now
        self.toolHost = toolHost
        self.attachmentStore = attachments
        self.thread = thread
        self.preferredModelID = thread?.modelID
        self.context = context
        self.registry = registry
        self.settings = settings
        self.models = models
        self.thinkingEnabled = thread?.thinkingEnabled ?? false
        self.toolsDisabled = thread?.toolsDisabled ?? false
    }

    var supportsThinking: Bool { model?.supportsThinking ?? false }

    /// The selected model can call tools, so the composer shows the Tools switch.
    var supportsTools: Bool { model?.capabilities.contains("tools") ?? false }

    /// Agent mode for this thread. On by default; a new chat keeps the choice until the first send creates the thread.
    var toolsEnabled: Bool { !toolsDisabled }

    func setToolsEnabled(_ on: Bool) {
        toolsDisabled = !on
        guard let thread else { return }
        thread.toolsDisabled = !on
        try? context.save()
    }

    func setThinkingEnabled(_ on: Bool) {
        thinkingEnabled = on
        guard let thread else { return }
        thread.thinkingEnabled = on
        try? context.save()
    }

    var messages: [MessageRecord] {
        (thread?.messages ?? []).sorted { $0.createdAt < $1.createdAt }
    }

    var isStreaming: Bool { phase == .streaming }

    private var resolution: ModelStore.Resolution { models.resolve(preferred: preferredModelID) }

    /// The model the next message goes to.
    var model: ModelDescriptor? { resolution.model }

    /// One line shown when this thread's saved model cannot be used and another one takes over.
    var modelNotice: String? {
        let resolution = resolution
        guard resolution.preferredUnavailable else { return nil }
        guard let fallback = resolution.model else { return "The model used earlier is unavailable. Choose another model." }
        return "The model used earlier is unavailable. Using \(fallback.shortName)."
    }

    /// Applies to the next message in this thread, is saved on the thread, and becomes the default for new chats.
    func choose(_ model: ModelDescriptor) {
        preferredModelID = model.id
        models.select(model)
        guard let thread else { return }
        thread.modelID = model.id
        do {
            try save(context)
        } catch {
            errorMessage = "Could not save the chat: \(error.localizedDescription)"
        }
    }

    var canSend: Bool {
        phase == .idle && ingesting == 0
            && (!input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pending.isEmpty)
    }

    // MARK: Attachments

    /// Under the composer: pending photos and a model that cannot see them.
    var attachmentNote: String? { AttachmentLogic.note(for: pending, model: model) }

    /// A vision model to switch to, offered next to the note.
    var visionAlternative: ModelDescriptor? {
        attachmentNote == nil ? nil : AttachmentLogic.visionAlternative(in: models.models)
    }

    func switchToVisionModel() {
        if let alternative = visionAlternative { choose(alternative) }
    }

    /// Photos or camera images as the bytes the system gave us.
    func attachImages(_ images: [(data: Data, filename: String)]) {
        add(images.count) { store, index in try await AttachmentIngest.image(from: images[index].data, filename: images[index].filename, store: store) }
    }

    /// Files from the Files importer.
    func attachFiles(_ urls: [URL]) {
        add(urls.count) { store, index in try await AttachmentIngest.file(at: urls[index], store: store) }
    }

    func removePending(_ attachment: ChatAttachment) {
        guard pending.contains(where: { $0.id == attachment.id }) else { return }
        pending.removeAll { $0.id == attachment.id }
        failedAttachmentIDs.remove(attachment.id)
        attachmentStore.remove(attachment)
    }

    /// Starts one reader per item; each result lands in `pending` in the order the items were picked.
    private func add(_ count: Int, _ read: @escaping @Sendable (AttachmentStore, Int) async throws -> ChatAttachment) {
        let room = max(0, AttachmentLogic.maxPerMessage - pending.count - ingesting)
        if count > room { errorMessage = "You can attach up to \(AttachmentLogic.maxPerMessage) files to a message." }
        let store = attachmentStore
        for index in 0..<min(count, room) {
            ingesting += 1
            Task { [weak self] in
                do {
                    let attachment = try await read(store, index)
                    self?.finishIngest(.success(attachment))
                } catch {
                    self?.finishIngest(.failure(error))
                }
            }
        }
    }

    private func finishIngest(_ result: Result<ChatAttachment, Error>) {
        ingesting -= 1
        switch result {
        case .success(let attachment): pending.append(attachment)
        case .failure(let error): errorMessage = error.localizedDescription
        }
    }

    /// The last reply can be regenerated, and a failed send can be retried.
    var canRegenerate: Bool {
        guard phase == .idle, let last = messages.last else { return false }
        return last.role == .assistant || last.role == .user
    }

    func dismissError() { errorMessage = nil }

    @discardableResult
    func send() -> Task<Void, Never>? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend else { return nil }
        guard let model = self.model else {
            errorMessage = "Choose a model first."
            return nil
        }
        // Files move first: if one cannot, nothing is sent and every file stays under the field.
        let threadID = thread?.id ?? draftThreadID
        guard let adopted = adoptPending(into: threadID) else { return nil }
        let thread = ensureThread(id: threadID, firstMessage: text.isEmpty ? (adopted.first?.filename ?? "Attachment") : text)
        models.telemetry.track(.messageSent(source: model.source))
        let user = MessageRecord(role: .user, content: text)
        context.insert(user)
        user.thread = thread
        user.attachments = adopted
        pending = []
        input = ""
        return startStream(model: model, thread: thread)
    }

    /// A preset with pickers (tone, language) waits here for the user's choices. The chat screen shows its sheet.
    var presetNeedingChoices: PromptPreset?

    /// Fills the composer with the preset prompt so the user can edit before sending. A preset with pickers opens
    /// its choices first.
    func usePreset(_ preset: PromptPreset) {
        if preset.hasOptions {
            presetNeedingChoices = preset
            return
        }
        input = preset.prompt
        focusTick += 1
    }

    /// The choices are made: the prompt for them plus the message goes out as one send.
    @discardableResult
    func finishChoices(_ preset: PromptPreset, selection: PresetSelection, message: String) -> Task<Void, Never>? {
        presetNeedingChoices = nil
        input = PresetOptionsLogic.composerText(preset, selection: selection, message: message)
        focusTick += 1
        return send()
    }

    /// A chat opened from outside the app: the composer gets the request's text and preset, and the message goes out
    /// when the request says so.
    @discardableResult
    func start(_ request: InboundChat, preset: PromptPreset?) -> Task<Void, Never>? {
        input = InboundChatLogic.composerText(preset: preset, text: request.text)
        focusTick += 1
        return request.sendNow ? send() : nil
    }

    @discardableResult
    func sendNow(_ preset: PromptPreset) -> Task<Void, Never>? {
        guard phase == .idle else { return nil }
        input = preset.resolvedPrompt
        return send()
    }

    func stop() {
        task?.cancel()
    }

    @discardableResult
    func regenerate() -> Task<Void, Never>? {
        guard canRegenerate, let thread, let model = self.model else { return nil }
        if let last = messages.last, last.role == .assistant { remove(last) }
        guard messages.last?.role == .user else { return nil }
        return startStream(model: model, thread: thread)
    }

    // MARK: - Private

    /// Drops the message from the relationship first so `messages` is correct before the next save.
    private func remove(_ message: MessageRecord) {
        message.thread?.messages.removeAll { $0.id == message.id }
        context.delete(message)
    }

    /// Moves the pending files into the thread's folder. `nil` when one cannot move: it stays pending and
    /// marked, and an error says which file to remove or attach again. A file that is already gone is found
    /// before anything moves, so a failed send leaves the others where they were.
    private func adoptPending(into threadID: UUID) -> [ChatAttachment]? {
        var failed = pending.filter { !attachmentStore.exists($0) }
        var result = pending
        if failed.isEmpty {
            for index in result.indices {
                do {
                    result[index] = try attachmentStore.adopt(result[index], intoThread: threadID)
                } catch {
                    failed.append(result[index])
                }
            }
        }
        failedAttachmentIDs = Set(failed.map(\.id))
        guard failed.isEmpty else {
            pending = result
            errorMessage = "Could not send \(failed.map(\.filename).joined(separator: ", ")). Remove it and attach it again."
            return nil
        }
        return result
    }

    private func ensureThread(id: UUID, firstMessage: String) -> ThreadRecord {
        if let thread { return thread }
        let created = ThreadRecord(id: id, title: ThreadListLogic.title(fromFirstMessage: firstMessage))
        created.thinkingEnabled = thinkingEnabled
        created.toolsDisabled = toolsDisabled
        context.insert(created)
        thread = created
        onThreadCreated?(created.id)
        return created
    }

    /// The chat's attachments, and only the user's own words and files as the texts a tool may trust.
    static func toolContext(for thread: ThreadRecord, modelSource: ModelSource? = nil) -> ToolContext {
        let all = thread.messages.flatMap { $0.attachments }
        let user = thread.messages.filter { $0.role == .user }
        let texts = user.flatMap { [$0.content] + $0.attachments.compactMap(\.extractedText) }
        return ToolContext(attachments: all, userTexts: texts, modelSource: modelSource)
    }

    private func startStream(model: ModelDescriptor, thread: ThreadRecord) -> Task<Void, Never> {
        phase = .streaming
        errorMessage = nil
        loadingModelName = (model.source == .gguf || model.source == .mlx) ? model.shortName : nil
        thread.modelID = model.id
        preferredModelID = model.id
        let assistant = MessageRecord(role: .assistant, content: "", modelName: model.shortName, modelID: model.id)
        let history = thread.orderedMessages
        context.insert(assistant)
        assistant.thread = thread
        let params = settings.generationParams
        let host = toolsEnabled && model.capabilities.contains("tools") ? toolHost(Self.toolContext(for: thread, modelSource: model.source)) : nil
        let stream = registry.engine(for: model).stream(
            model: model, messages: history, params: params,
            tools: host?.specs.isEmpty == false ? host : nil)

        let telemetry = models.telemetry
        let source = model.source
        let started = ContinuousClock.now
        let startedAt = now()
        let clock = now
        let knownModels = models.models
        let task = Task { [weak self] in
            var failure: String?
            var firstTokenSeen = false
            var reported: ResponseMetadata?
            var tokens: (prompt: Int, completion: Int)?
            var ttftMs: Int?
            // A fast local model makes 50 tokens a second; the screen takes them 20 times a second.
            var pending = TextCoalescer(interval: Self.textInterval)
            do {
                for try await delta in stream {
                    // A chunk that was already buffered when the user pressed stop is dropped.
                    if Task.isCancelled { continue }
                    // The thread can be deleted while it streams; stop writing into models that are gone.
                    if Self.isGone(assistant) || Self.isGone(thread) { break }
                    if case .text = delta {} else if let held = pending.flush() { assistant.content += held }
                    switch delta {
                    case .text(let piece):
                        if !firstTokenSeen {
                            firstTokenSeen = true
                            self?.loadingModelName = nil
                            ttftMs = Self.milliseconds(clock() - startedAt)
                            telemetry.track(.firstTokenMs(TelemetryEvent.milliseconds(ContinuousClock.now - started), source: source))
                        }
                        if let text = pending.add(piece, now: clock()) { assistant.content += text }
                    case .toolCall(let call): assistant.toolSteps.append(ToolStep(call: call, result: nil))
                    case .toolResult(let result): Self.fill(result, in: assistant)
                    case .usage(let prompt, let completion): tokens = (prompt, completion)
                    case .metadata(let metadata): reported = metadata
                    case .done: break
                    }
                }
            } catch is CancellationError {
                // Stopped by the user.
            } catch {
                failure = error.localizedDescription
            }
            if Self.isGone(assistant) || Self.isGone(thread) {
                self?.abandon()
                return
            }
            if let held = pending.flush() { assistant.content += held }
            if !assistant.content.isEmpty || !assistant.toolSteps.isEmpty {
                assistant.metadata = Self.finalMetadata(
                    reported, tokens: tokens, model: model, ttftMs: ttftMs,
                    totalMs: Self.milliseconds(clock() - startedAt),
                    nameOf: { id in knownModels.first { $0.wireID == id }?.displayName })
            }
            self?.finish(assistant, in: thread, failure: failure)
        }
        self.task = task
        return task
    }

    /// A deleted record (or one whose context is gone) must not be read or written: SwiftData traps on it.
    static func isGone(_ model: some PersistentModel) -> Bool {
        model.isDeleted || model.modelContext == nil
    }

    /// The thread was deleted during the reply: nothing to save, the view model just returns to idle.
    private func abandon() {
        phase = .idle
        task = nil
        loadingModelName = nil
    }

    /// Seconds between screen updates while text streams in.
    static let textInterval: TimeInterval = 0.05

    static func milliseconds(_ seconds: TimeInterval) -> Int { max(0, Int((seconds * 1000).rounded())) }

    /// The metadata stored with a reply: what the server reported (or "On device" and cost 0 for
    /// local and Apple models), plus token counts and the timings measured here.
    static func finalMetadata(
        _ reported: ResponseMetadata?, tokens: (prompt: Int, completion: Int)?, model: ModelDescriptor,
        ttftMs: Int?, totalMs: Int, nameOf: (String) -> String?
    ) -> ResponseMetadata {
        var metadata = reported ?? ResponseMetadata()
        if model.source != .anyrouter {
            metadata.servedModelID = model.id
            metadata.servedModelName = model.shortName
            metadata.provider = "On device"
            metadata.costUSD = 0
        } else {
            let served = metadata.servedModelID ?? model.wireID
            metadata.servedModelID = served
            metadata.servedModelName = served == model.wireID
                ? model.shortName : (nameOf(served) ?? ResponseFormat.prettyName(served))
        }
        if metadata.promptTokens == nil { metadata.promptTokens = tokens?.prompt }
        if metadata.completionTokens == nil { metadata.completionTokens = tokens?.completion }
        metadata.ttftMs = ttftMs
        metadata.totalMs = totalMs
        return metadata
    }

    private static func fill(_ result: ToolResult, in assistant: MessageRecord) {
        var steps = assistant.toolSteps
        guard let index = steps.firstIndex(where: { $0.call.id == result.callID }) else { return }
        steps[index].result = result
        assistant.toolSteps = steps
    }

    private func finish(_ assistant: MessageRecord, in thread: ThreadRecord, failure: String?) {
        // Nothing is running any more, so a step without a result was cut off.
        var steps = assistant.toolSteps
        for index in steps.indices where steps[index].result == nil {
            steps[index].result = ToolResult(
                callID: steps[index].call.id, name: steps[index].call.name,
                text: ToolRowLogic.cancelledText, isError: true)
        }
        if steps != assistant.toolSteps { assistant.toolSteps = steps }
        let gotReply = failure == nil && !assistant.content.isEmpty
        if assistant.content.isEmpty && steps.isEmpty { remove(assistant) }
        thread.updatedAt = Date()
        phase = .idle
        task = nil
        loadingModelName = nil
        errorMessage = failure
        if gotReply { settings.noteSuccessfulChat() }
        do {
            try save(context)
        } catch {
            errorMessage = "Could not save the chat: \(error.localizedDescription)"
        }
    }
}
