import Foundation
import Observation
import SwiftData

/// Send, stream, stop and regenerate for one thread. A new chat has no thread until the first send.
@MainActor @Observable
final class ChatViewModel {
    enum Phase: Equatable { case idle, streaming, compacting }

    var input = ""
    private(set) var phase: Phase = .idle
    private(set) var errorMessage: String?
    /// Under the messages when the last request left web tools out because the device was offline.
    private(set) var offlineToolNote: String?
    /// Name of the local model that is loading or reading the prompt, until its first token arrives. Nil otherwise.
    /// The UI shows "Loading <name>…" and stays usable; Stop cancels.
    private(set) var loadingModelName: String?
    private(set) var thread: ThreadRecord?
    /// Bumps when the composer should take focus (after a preset fills it).
    private(set) var focusTick = 0
    /// Bumps when the composer should start dictating (a "Start voice" request).
    private(set) var voiceTick = 0
    /// Per-thread "Enable thinking"; a new chat keeps it here until the first send creates the thread.
    private(set) var thinkingEnabled = false
    private(set) var toolsDisabled = false
    /// Instructions for this chat only; they replace the global ones. A new chat keeps them until the first send.
    private(set) var chatInstructions: String?
    /// Model id saved on this thread. `nil` follows the default for new chats.
    private(set) var preferredModelID: String?
    /// Files and photos waiting under the composer for the next send.
    private(set) var pending: [ChatAttachment] = []
    /// Attachments still being read (images are shrunk, text and OCR are read off the main actor).
    private(set) var ingesting = 0
    /// The readers behind `ingesting`, so a caller can wait for them instead of polling.
    @ObservationIgnored private var ingestTasks: [Task<Void, Never>] = []
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
    /// Whether the device has a connection, asked at each send.
    @ObservationIgnored private let isOnline: @MainActor () -> Bool
    /// Whether an offline request had web tools to leave out, so the chat can say so.
    @ObservationIgnored private let skipsToolsOffline: @MainActor (ToolContext) -> Bool
    /// Web search for models that run no tool loop (local GGUF and MLX).
    @ObservationIgnored private let webSearch: PreSearcher
    @ObservationIgnored let attachmentStore: AttachmentStore
    @ObservationIgnored private var task: Task<Void, Never>?

    init(thread: ThreadRecord?, context: ModelContext, registry: EngineRegistry,
         settings: AppSettings, models: ModelStore,
         toolHost: @escaping @MainActor (ToolContext) -> (any ToolHost)? = { _ in nil },
         isOnline: @escaping @MainActor () -> Bool = { true },
         skipsToolsOffline: @escaping @MainActor (ToolContext) -> Bool = { _ in false },
         webSearch: PreSearcher = .none,
         attachments: AttachmentStore = .shared,
         save: @escaping (ModelContext) throws -> Void = { try $0.save() },
         now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.save = save
        self.now = now
        self.toolHost = toolHost
        self.isOnline = isOnline
        self.skipsToolsOffline = skipsToolsOffline
        self.webSearch = webSearch
        self.attachmentStore = attachments
        self.thread = thread
        self.preferredModelID = thread?.modelID
        self.context = context
        self.registry = registry
        self.settings = settings
        self.models = models
        self.thinkingEnabled = thread?.thinkingEnabled ?? false
        self.toolsDisabled = thread?.toolsDisabled ?? false
        self.chatInstructions = thread?.instructions
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

    /// Blank text removes the override, so the global instructions apply again.
    func setChatInstructions(_ text: String?) {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        chatInstructions = trimmed.isEmpty ? nil : trimmed
        guard let thread else { return }
        thread.instructions = chatInstructions
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

    /// Changes when a reply starts or ends and when its local model has finished loading: the moments the memory
    /// readout can change because of this chat.
    var memoryActivity: Int { (isStreaming ? 1 : 0) | (loadingModelName == nil ? 2 : 0) }

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

    // MARK: Compaction

    /// A summary is being written, by hand or because the chat is filling the model's window.
    private(set) var isCompacting = false
    /// Said under the messages when the chat could not be shortened and goes out as it is. Cleared by the next send.
    private(set) var compactionNote: String?

    /// What the last reply row says while the chat is being shortened, in place of the typing dots.
    var statusNote: String? { isCompacting ? String(localized: "Shortening the conversation…") : nil }

    var compactions: [Compaction] {
        guard let thread else { return [] }
        return thread.compactions
    }

    private var windowTokens: Int? { model.flatMap { CompactionLogic.window(for: $0) } }

    /// The messages a compaction by hand would fold, or nil when the chat is too short to gain from it.
    private func manualPlan() -> CompactionPlan? {
        guard let thread else { return nil }
        return CompactionLogic.plan(
            messages: thread.orderedMessages, compaction: thread.compactions.last, window: windowTokens,
            keepRecent: CompactionLogic.keepRecentManual)
    }

    var canCompact: Bool { phase == .idle && model != nil && manualPlan() != nil }

    /// "Compact conversation" in the chat menu: folds the older messages into a summary written by the current model.
    @discardableResult
    func compactConversation() -> Task<Void, Never>? {
        guard phase == .idle, let thread, let model = self.model, let plan = manualPlan() else { return nil }
        if blockedOffline(model) { return nil }
        phase = .compacting
        errorMessage = nil
        let task = Task { [weak self] in
            guard let self else { return }
            let folded = await self.fold(plan, model: model, thread: thread)
            if !folded, !Task.isCancelled { self.errorMessage = String(localized: "Could not shorten the conversation.") }
            self.phase = .idle
            self.task = nil
        }
        self.task = task
        return task
    }

    /// Asks the model for the summary of `plan` and keeps it with the thread. False when nothing came back.
    private func fold(_ plan: CompactionPlan, model: ModelDescriptor, thread: ThreadRecord) async -> Bool {
        isCompacting = true
        defer { isCompacting = false }
        guard let summary = await summarize(plan, model: model), !Self.isGone(thread) else { return false }
        thread.compactions = thread.compactions + [CompactionLogic.record(summary: summary, plan: plan, now: Date())]
        // A failed save is reported by the save that ends the next reply; the summary stays in memory until then.
        try? save(context)
        return true
    }

    private func summarize(_ plan: CompactionPlan, model: ModelDescriptor) async -> String? {
        let request = CompactionLogic.request(for: plan)
        var params = GenerationParams()
        params.temperature = 0.2
        params.maxTokens = CompactionLogic.summaryTokens
        params.systemPrompt = request.system
        var splitter = ReasoningSplitter()
        var text = ""
        do {
            for try await delta in registry.engine(for: model).stream(
                model: model, messages: request.messages, params: params, tools: nil) {
                if Task.isCancelled { return nil }
                if case .text(let piece) = delta { text += splitter.feed(piece).text }
            }
        } catch {
            return nil
        }
        text += splitter.finish().text
        return Task.isCancelled ? nil : CompactionLogic.cleanSummary(text)
    }

    /// The chat is about to fill the model's window: what to fold first, so the reply has room.
    /// `placeholder` is the reply being written: it is in the thread already, empty, and is not part of the chat yet.
    private func automaticPlan(
        thread: ThreadRecord, model: ModelDescriptor, systemPrompt: String?, sent: [ChatMessage], placeholder: UUID
    ) -> CompactionPlan? {
        let window = CompactionLogic.window(for: model)
        let used = CompactionLogic.usedTokens(systemPrompt: systemPrompt, summary: nil, messages: sent)
        guard CompactionLogic.needsCompaction(used: used, window: window) else { return nil }
        return CompactionLogic.plan(
            messages: thread.orderedMessages.filter { $0.id != placeholder }, compaction: thread.compactions.last,
            window: window, keepRecent: CompactionLogic.keepRecentAutomatic)
    }

    var canSend: Bool {
        phase == .idle && ingesting == 0
            && (!input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pending.isEmpty)
    }

    // MARK: Attachments

    /// Under the composer: pending photos and a model that cannot see them.
    var attachmentNote: String? {
        AttachmentLogic.note(for: pending, model: model, alternative: AttachmentLogic.visionAlternative(in: models.models))
    }

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

    /// Text read from a photo (Read text in the + menu), waiting for the user to choose what to do with it.
    var scannedText: ScannedText?

    /// Reads the text in photos on the device. Nothing is attached: the text goes to a sheet, then the composer.
    func readText(from images: [Data]) {
        guard !images.isEmpty else { return }
        ingesting += 1
        ingestTasks.append(Task { [weak self] in
            let texts = await TextExtraction.texts(inImages: images)
            self?.finishReading(texts)
        })
    }

    /// Returns when every attachment and scan started so far has been read, or has failed.
    func finishIngesting() async {
        let running = ingestTasks
        ingestTasks.removeAll()
        for task in running { await task.value }
    }

    private func finishReading(_ texts: [String]) {
        ingesting -= 1
        if texts.isEmpty {
            errorMessage = OCRLogic.noTextMessage
        } else {
            scannedText = ScannedText(text: OCRLogic.join(texts))
        }
    }

    /// The scan goes into the composer, with a preset's prompt (and the user's picks) in front when one was chosen.
    func useScan(_ preset: PromptPreset?, selection: PresetSelection, text: String) {
        scannedText = nil
        if let preset {
            fill(PresetOptionsLogic.composerText(preset, selection: selection, message: text))
        } else {
            fill(OCRLogic.appended(text, to: input))
        }
    }

    // MARK: @ mentions

    /// Plugins and files the user named with @ for the next message. The send takes them.
    private(set) var mentions: [MentionItem] = []

    /// Files the @ list offers: those waiting under the field, then those of this chat.
    var mentionableFiles: [ChatAttachment] {
        var seen = Set<UUID>()
        return (pending + messages.flatMap(\.attachments)).filter { seen.insert($0.id).inserted }
    }

    /// Takes the "@words" out of the field and keeps the choice as a chip.
    func addMention(_ item: MentionItem) {
        let cleaned = ComposerMention.removingQuery(from: input)
        if cleaned != input {
            input = cleaned
            ownText = cleaned
        }
        if !mentions.contains(where: { $0.id == item.id }) { mentions.append(item) }
    }

    func removeMention(_ item: MentionItem) { mentions.removeAll { $0.id == item.id } }

    /// A preset chosen in the @ list: the "@words" leave the field, and the preset opens its choices with the rest of
    /// the field as the message.
    func choosePreset(_ preset: PromptPreset) {
        let cleaned = ComposerMention.removingQuery(from: input)
        if cleaned != input {
            input = cleaned
            ownText = cleaned
        }
        usePreset(preset)
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
            ingestTasks.append(Task { [weak self] in
                do {
                    let attachment = try await read(store, index)
                    self?.finishIngest(.success(attachment))
                } catch {
                    self?.finishIngest(.failure(error))
                }
            })
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

    /// Shows a message in the banner above the composer, for what the chat cannot do right now.
    func showError(_ message: String) { errorMessage = message }

    /// The title of a chat whose first message is only files: the first file's name.
    static func attachmentTitle(_ files: [ChatAttachment]) -> String {
        guard let first = files.first else { return "Attachment" }
        return first.filename
    }

    @discardableResult
    func send() -> Task<Void, Never>? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend else { return nil }
        guard let model = self.model else {
            errorMessage = "Choose a model first."
            return nil
        }
        if blockedOffline(model) { return nil }
        // Files move first: if one cannot, nothing is sent and every file stays under the field.
        let threadID = thread?.id ?? draftThreadID
        guard let adopted = adoptPending(into: threadID) else { return nil }
        let thread = ensureThread(id: threadID, firstMessage: text.isEmpty ? Self.attachmentTitle(adopted) : text)
        models.telemetry.track(.messageSent(source: model.source))
        let user = MessageRecord(role: .user, content: text)
        context.insert(user)
        user.thread = thread
        user.attachments = adopted
        pending = []
        input = ""
        let named = mentions
        mentions = []
        return startStream(model: model, thread: thread, mentions: named)
    }

    /// A preset with pickers (tone, language) waits here for the user's choices. The chat screen shows its sheet.
    var presetNeedingChoices: PromptPreset?

    /// True while presets are offered for a paste: set by a paste into the composer, cleared by the next edit that is
    /// not a paste, by a send, and by a choice.
    private(set) var pasteOffered = false
    /// Text the app put in the composer itself (a preset, a Shortcut). The change that brings exactly this text is not a paste.
    @ObservationIgnored private var ownText: String?

    func fill(_ text: String) {
        input = text
        ownText = text
        pasteOffered = false
        focusTick += 1
    }

    /// The composer calls this for every change of `input`. A big block that appears at once is a paste.
    func inputChanged(from old: String, to new: String) {
        let own = ownText
        ownText = nil
        pasteOffered = new != own && PasteOfferLogic.pastedText(from: old, to: new) != nil
    }

    /// Applies a preset to what was pasted: the composer gets the prompt, then the text, ready to edit or send.
    func applyToPaste(_ preset: PromptPreset) {
        if preset.hasOptions {
            // A preset with pickers (Reply to this) asks for its choices, with the pasted text as the message.
            pasteOffered = false
            presetNeedingChoices = preset
        } else {
            fill(PasteOfferLogic.apply(preset, to: input))
        }
    }

    func dismissPasteOffer() { pasteOffered = false }

    /// A preset tapped in the clipboard row, with the text read from the clipboard. A preset with pickers opens its
    /// choices with the text as the message; any other preset goes out at once.
    @discardableResult
    func useClipboard(_ preset: PromptPreset, text: String) -> Task<Void, Never>? {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return nil }
        if preset.hasOptions {
            fill(body)
            presetNeedingChoices = preset
            return nil
        }
        fill(PasteOfferLogic.apply(preset, to: body))
        return send()
    }

    /// Fills the composer with the preset prompt so the user can edit before sending. A preset with pickers opens
    /// its choices first.
    func usePreset(_ preset: PromptPreset) {
        if preset.hasOptions {
            presetNeedingChoices = preset
            return
        }
        fill(preset.prompt)
    }

    /// The choices are made: the prompt for them plus the message goes out as one send.
    @discardableResult
    func finishChoices(_ preset: PromptPreset, selection: PresetSelection, message: String) -> Task<Void, Never>? {
        presetNeedingChoices = nil
        fill(PresetOptionsLogic.composerText(preset, selection: selection, message: message))
        return send()
    }

    /// A chat opened from outside the app: the composer gets the request's text and preset, and the message goes out
    /// when the request says so.
    @discardableResult
    func start(_ request: InboundChat, preset: PromptPreset?) -> Task<Void, Never>? {
        if !request.files.isEmpty { attachFiles(request.files) }
        if !request.readsTextFrom.isEmpty { readText(from: request.readsTextFrom.compactMap { try? Data(contentsOf: $0) }) }
        if request.asksForText, let preset {
            // The preset's sheet has the system Paste button; the text so far is its message.
            fill(InboundChatLogic.composerText(preset: nil, text: request.text))
            presetNeedingChoices = preset
            return nil
        }
        fill(InboundChatLogic.composerText(preset: preset, text: request.text))
        if request.startsVoice { voiceTick += 1 }
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
        if blockedOffline(model) { return nil }
        if let last = messages.last, last.role == .assistant { remove(last) }
        guard messages.last?.role == .user else { return nil }
        return startStream(model: model, thread: thread)
    }

    // MARK: - Private

    /// A cloud model cannot answer without a connection: say so, and name the model on the device that can.
    private func blockedOffline(_ model: ModelDescriptor) -> Bool {
        guard !isOnline(), OfflineLogic.needsNetwork(model) else { return false }
        errorMessage = OfflineLogic.modelMessage(for: model, suggestion: OfflineLogic.suggestedModel(in: models.models))
        return true
    }

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
        created.instructions = chatInstructions
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

    private func startStream(model: ModelDescriptor, thread: ThreadRecord, mentions: [MentionItem] = []) -> Task<Void, Never> {
        phase = .streaming
        errorMessage = nil
        loadingModelName = (model.source == .gguf || model.source == .mlx) ? model.shortName : nil
        thread.modelID = model.id
        preferredModelID = model.id
        let assistant = MessageRecord(role: .assistant, content: "", modelName: model.shortName, modelID: model.id)
        // What goes out is the summary of the folded part of the chat and the messages after it.
        let live = CompactionLogic.context(messages: thread.orderedMessages, compaction: thread.compactions.last)
        // The plugins and files the user named with @ are asked for in this request only; the saved message stays as typed.
        let history = ComposerMention.applying(mentions, to: live.messages)
        context.insert(assistant)
        assistant.thread = thread
        var params = settings.generationParams
        let basePrompt = InstructionsLogic.effective(chat: chatInstructions, global: settings.systemPrompt)
        params.systemPrompt = CompactionLogic.systemPrompt(base: basePrompt, summary: live.summary)
        let autoPlan = automaticPlan(
            thread: thread, model: model, systemPrompt: params.systemPrompt, sent: history, placeholder: assistant.id)
        compactionNote = nil
        var host: (any ToolHost)?
        offlineToolNote = nil
        if (toolsEnabled || !mentions.isEmpty) && model.capabilities.contains("tools") {
            var toolContext = Self.toolContext(for: thread, modelSource: model.source)
            toolContext.forcedSourceIDs = ComposerMention.forcedSourceIDs(of: mentions)
            toolContext.isOffline = !isOnline()
            host = toolHost(toolContext)
            if skipsToolsOffline(toolContext) { offlineToolNote = OfflineLogic.toolNote }
        }
        let engine = registry.engine(for: model)
        let tools = host?.specs.isEmpty == false ? host : nil
        // A model without a tool loop gets a search run for it when its question needs the web.
        var grounding: (query: String, context: ToolContext)?
        if toolsEnabled, tools == nil, WebGrounding.appliesTo(model.source), webSearch.isOn(model.source),
            let question = thread.orderedMessages.last(where: { $0.role == .user })?.content,
            WebGrounding.needsFreshInfo(question) {
            var searchContext = Self.toolContext(for: thread, modelSource: model.source)
            searchContext.isOffline = !isOnline()
            if searchContext.isOffline {
                offlineToolNote = OfflineLogic.toolNote
            } else {
                grounding = (WebGrounding.query(from: question), searchContext)
            }
        }

        let telemetry = models.telemetry
        let source = model.source
        let started = ContinuousClock.now
        let startedAt = now()
        let clock = now
        let knownModels = models.models
        let groundingPlan = grounding
        // Without a search the engine is asked now, as it always was; with one it is asked once the results are in.
        // A chat that is filling the window is shortened first, so the engine is asked once the summary is in.
        let earlyStream = groundingPlan == nil && autoPlan == nil
            ? engine.stream(model: model, messages: history, params: params, tools: tools) : nil
        let task = Task { [weak self] in
            let stream: AsyncThrowingStream<ChatDelta, Error>
            if let earlyStream {
                stream = earlyStream
            } else {
                var sent = history
                var sentParams = params
                if let plan = autoPlan, let self {
                    if await self.fold(plan, model: model, thread: thread) {
                        let rebuilt = CompactionLogic.context(
                            messages: thread.orderedMessages.filter { $0.id != assistant.id }, compaction: thread.compactions.last)
                        sent = ComposerMention.applying(mentions, to: rebuilt.messages)
                        sentParams.systemPrompt = CompactionLogic.systemPrompt(base: basePrompt, summary: rebuilt.summary)
                    } else {
                        self.compactionNote = String(localized: "Could not shorten the conversation. It was sent as it is.")
                    }
                }
                if let plan = groundingPlan, let self {
                    sent = await self.ground(sent, query: plan.query, context: plan.context, assistant: assistant)
                }
                stream = engine.stream(model: model, messages: sent, params: sentParams, tools: tools)
            }
            var failure: String?
            var firstTokenSeen = false
            var reported: ResponseMetadata?
            var tokens: (prompt: Int, completion: Int)?
            var ttftMs: Int?
            // A fast local model makes 50 tokens a second; the screen takes them 20 times a second.
            var pending = TextCoalescer(interval: Self.textInterval)
            // What the model thinks before it answers: sent as reasoning deltas, or inline as <think> in the text.
            var splitter = ReasoningSplitter()
            var thoughts = ReasoningRecorder()
            var thoughtsShownAt: TimeInterval?
            @MainActor func showThoughts(_ piece: String) {
                thoughts.add(piece, at: clock())
                let time = clock()
                if let last = thoughtsShownAt, time - last < Self.textInterval { return }
                thoughtsShownAt = time
                assistant.reasoning = thoughts.trace
            }
            @MainActor func endThoughts() {
                guard !thoughts.hasEnded, thoughts.trace != nil else { return }
                thoughts.end(at: clock())
                assistant.reasoning = thoughts.trace
            }
            do {
                for try await delta in stream {
                    // A chunk that was already buffered when the user pressed stop is dropped.
                    if Task.isCancelled { continue }
                    // The thread can be deleted while it streams; stop writing into models that are gone.
                    if Self.isGone(assistant) || Self.isGone(thread) { break }
                    if case .text = delta {} else if let held = pending.flush() { assistant.content += held }
                    switch delta {
                    case .reasoning(let piece):
                        self?.loadingModelName = nil
                        showThoughts(piece)
                    case .text(let piece):
                        let split = splitter.feed(piece)
                        if !split.reasoning.isEmpty {
                            self?.loadingModelName = nil
                            showThoughts(split.reasoning)
                        }
                        if split.text.isEmpty { continue }
                        endThoughts()
                        if !firstTokenSeen {
                            firstTokenSeen = true
                            self?.loadingModelName = nil
                            ttftMs = Self.milliseconds(clock() - startedAt)
                            telemetry.track(.firstTokenMs(TelemetryEvent.milliseconds(ContinuousClock.now - started), source: source))
                        }
                        if let text = pending.add(split.text, now: clock()) { assistant.content += text }
                    case .toolCall(let call):
                        endThoughts()
                        assistant.toolSteps.append(ToolStep(call: call, result: nil, sourceID: tools?.sourceID(forTool: call.name)))
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
            // A tag that never closed or never opened: the held characters are what they were.
            let rest = splitter.finish()
            if !rest.reasoning.isEmpty { showThoughts(rest.reasoning) }
            if !rest.text.isEmpty, let text = pending.add(rest.text, now: clock()) { assistant.content += text }
            if let held = pending.flush() { assistant.content += held }
            endThoughts()
            if thoughts.trace != nil { assistant.reasoning = thoughts.trace }
            if !assistant.content.isEmpty || !assistant.toolSteps.isEmpty || assistant.reasoning != nil {
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
    nonisolated static let textInterval: TimeInterval = 0.05

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

    /// Runs the search with a row in the reply ("Searching the web for …") and returns the history with the results in
    /// front of the question. Without results the history is returned as it was and the row is removed.
    private func ground(_ history: [ChatMessage], query: String, context: ToolContext, assistant: MessageRecord) async -> [ChatMessage] {
        let call = ToolCall(
            id: UUID().uuidString, name: WebSearchBinding.name,
            argumentsJSON: JSONValue.object(["query": .string(query)]).jsonString())
        assistant.toolSteps.append(ToolStep(call: call, result: nil, sourceID: ToolSourceCatalog.anyRouter.id))
        guard let answer = await webSearch.search(query, context) else {
            assistant.toolSteps.removeAll { $0.call.id == call.id }
            return history
        }
        Self.fill(ToolResult(callID: call.id, name: call.name, text: answer.text, isError: answer.isError), in: assistant)
        guard !answer.isError, let text = WebGrounding.context(for: WebGrounding.parse(answer.text)) else { return history }
        return WebGrounding.applying(text, to: history)
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
        if assistant.content.isEmpty && steps.isEmpty && assistant.reasoning == nil { remove(assistant) }
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
