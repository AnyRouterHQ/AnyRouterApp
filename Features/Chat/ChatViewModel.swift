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

    /// Called once when the first send creates the thread.
    @ObservationIgnored var onThreadCreated: (@MainActor (UUID) -> Void)?

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let registry: EngineRegistry
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let models: ModelStore
    @ObservationIgnored private let save: (ModelContext) throws -> Void
    @ObservationIgnored private let toolHost: @MainActor () -> (any ToolHost)?
    @ObservationIgnored private var task: Task<Void, Never>?

    init(thread: ThreadRecord?, context: ModelContext, registry: EngineRegistry,
         settings: AppSettings, models: ModelStore,
         toolHost: @escaping @MainActor () -> (any ToolHost)? = { nil },
         save: @escaping (ModelContext) throws -> Void = { try $0.save() }) {
        self.save = save
        self.toolHost = toolHost
        self.thread = thread
        self.context = context
        self.registry = registry
        self.settings = settings
        self.models = models
        self.thinkingEnabled = thread?.thinkingEnabled ?? false
    }

    var supportsThinking: Bool { models.selected?.supportsThinking ?? false }

    /// The selected model can call tools, so the composer shows the Tools switch.
    var supportsTools: Bool { models.selected?.capabilities.contains("tools") ?? false }

    var toolsEnabled: Bool { settings.toolsEnabled }

    func setToolsEnabled(_ on: Bool) { settings.toolsEnabled = on }

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
        guard let model = models.selected else {
            errorMessage = "Choose a model first."
            return nil
        }
        let thread = ensureThread(firstMessage: text)
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
        guard canRegenerate, let thread, let model = models.selected else { return nil }
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
        context.insert(created)
        thread = created
        onThreadCreated?(created.id)
        return created
    }

    private func startStream(model: ModelDescriptor, thread: ThreadRecord) -> Task<Void, Never> {
        phase = .streaming
        errorMessage = nil
        thread.modelID = model.id
        let assistant = MessageRecord(role: .assistant, content: "")
        let history = thread.orderedMessages
        context.insert(assistant)
        assistant.thread = thread
        let params = settings.generationParams
        let host = settings.toolsEnabled && model.capabilities.contains("tools") ? toolHost() : nil
        let stream = registry.engine(for: model).stream(
            model: model, messages: history, params: params,
            tools: host?.specs.isEmpty == false ? host : nil)

        let task = Task { [weak self] in
            var failure: String?
            do {
                for try await delta in stream {
                    // A chunk that was already buffered when the user pressed stop is dropped.
                    if Task.isCancelled { continue }
                    switch delta {
                    case .text(let piece): assistant.content += piece
                    case .toolCall(let call): assistant.toolSteps.append(ToolStep(call: call, result: nil))
                    case .toolResult(let result): Self.fill(result, in: assistant)
                    case .usage, .done: break
                    }
                }
            } catch is CancellationError {
                // Stopped by the user.
            } catch {
                failure = error.localizedDescription
            }
            self?.finish(assistant, in: thread, failure: failure)
        }
        self.task = task
        return task
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
