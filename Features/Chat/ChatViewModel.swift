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
    private(set) var thread: ThreadRecord?
    /// Bumps when the composer should take focus (after a preset fills it).
    private(set) var focusTick = 0
    /// Per-thread "Enable thinking"; a new chat keeps it here until the first send creates the thread.
    private(set) var thinkingEnabled = false
    private(set) var toolsDisabled = false
    /// Model id saved on this thread. `nil` follows the default for new chats.
    private(set) var preferredModelID: String?

    /// Called once when the first send creates the thread.
    @ObservationIgnored var onThreadCreated: (@MainActor (UUID) -> Void)?

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let registry: EngineRegistry
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let models: ModelStore
    @ObservationIgnored private let save: (ModelContext) throws -> Void
    /// Seconds from any steady clock. Injected so timings are testable.
    @ObservationIgnored private let now: () -> TimeInterval
    @ObservationIgnored private let toolHost: @MainActor () -> (any ToolHost)?
    @ObservationIgnored private var task: Task<Void, Never>?

    init(thread: ThreadRecord?, context: ModelContext, registry: EngineRegistry,
         settings: AppSettings, models: ModelStore,
         toolHost: @escaping @MainActor () -> (any ToolHost)? = { nil },
         save: @escaping (ModelContext) throws -> Void = { try $0.save() },
         now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.save = save
        self.now = now
        self.toolHost = toolHost
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
            try context.save()
        } catch {
            errorMessage = "Could not save the chat: \(error.localizedDescription)"
        }
    }

    var canSend: Bool {
        phase == .idle && !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
        guard phase == .idle, !text.isEmpty else { return nil }
        guard let model = self.model else {
            errorMessage = "Choose a model first."
            return nil
        }
        let thread = ensureThread(firstMessage: text)
        models.telemetry.track(.messageSent(source: model.source))
        let user = MessageRecord(role: .user, content: text)
        context.insert(user)
        user.thread = thread
        input = ""
        return startStream(model: model, thread: thread)
    }

    /// Fills the composer with the preset prompt so the user can edit before sending.
    func usePreset(_ preset: PromptPreset) {
        input = preset.prompt
        focusTick += 1
    }

    @discardableResult
    func sendNow(_ preset: PromptPreset) -> Task<Void, Never>? {
        guard phase == .idle else { return nil }
        input = preset.prompt
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

    private func ensureThread(firstMessage: String) -> ThreadRecord {
        if let thread { return thread }
        let created = ThreadRecord(title: ThreadListLogic.title(fromFirstMessage: firstMessage))
        created.thinkingEnabled = thinkingEnabled
        created.toolsDisabled = toolsDisabled
        context.insert(created)
        thread = created
        onThreadCreated?(created.id)
        return created
    }

    private func startStream(model: ModelDescriptor, thread: ThreadRecord) -> Task<Void, Never> {
        phase = .streaming
        errorMessage = nil
        thread.modelID = model.id
        preferredModelID = model.id
        let assistant = MessageRecord(role: .assistant, content: "", modelName: model.shortName, modelID: model.id)
        let history = thread.orderedMessages
        context.insert(assistant)
        assistant.thread = thread
        let params = settings.generationParams
        let host = toolsEnabled && model.capabilities.contains("tools") ? toolHost() : nil
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
            do {
                for try await delta in stream {
                    // A chunk that was already buffered when the user pressed stop is dropped.
                    if Task.isCancelled { continue }
                    switch delta {
                    case .text(let piece):
                        if !firstTokenSeen {
                            firstTokenSeen = true
                            ttftMs = Self.milliseconds(clock() - startedAt)
                            telemetry.track(.firstTokenMs(TelemetryEvent.milliseconds(ContinuousClock.now - started), source: source))
                        }
                        assistant.content += piece
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
        if assistant.content.isEmpty && steps.isEmpty { remove(assistant) }
        thread.updatedAt = Date()
        phase = .idle
        task = nil
        errorMessage = failure
        do {
            try save(context)
        } catch {
            errorMessage = "Could not save the chat: \(error.localizedDescription)"
        }
    }
}
