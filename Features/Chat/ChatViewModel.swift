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

    /// Called once when the first send creates the thread.
    @ObservationIgnored var onThreadCreated: (@MainActor (UUID) -> Void)?

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let registry: EngineRegistry
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let models: ModelStore
    @ObservationIgnored private var task: Task<Void, Never>?

    init(thread: ThreadRecord?, context: ModelContext, registry: EngineRegistry,
         settings: AppSettings, models: ModelStore) {
        self.thread = thread
        self.context = context
        self.registry = registry
        self.settings = settings
        self.models = models
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
        let stream = registry.engine(for: model).stream(model: model, messages: history, params: params)

        let task = Task { [weak self] in
            var failure: String?
            do {
                for try await delta in stream {
                    if Task.isCancelled { break }
                    if case .text(let piece) = delta { assistant.content += piece }
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

    private func finish(_ assistant: MessageRecord, in thread: ThreadRecord, failure: String?) {
        if assistant.content.isEmpty { remove(assistant) }
        thread.updatedAt = Date()
        phase = .idle
        task = nil
        errorMessage = failure
        do {
            try context.save()
        } catch {
            errorMessage = "Could not save the chat: \(error.localizedDescription)"
        }
    }
}
