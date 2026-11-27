import Foundation

/// A message typed while a reply was still streaming. It waits in its thread until the reply ends.
struct QueueItem: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var text: String
    /// Files already moved into the thread, as they go out with the message.
    var attachments: [ChatAttachment] = []
}

/// The messages waiting in one thread, in the order they were typed. Stored with the thread as JSON.
struct MessageQueue: Codable, Equatable, Sendable {
    var items: [QueueItem] = []
    /// A failed or stopped reply, or a send that could not start: nothing goes out until the person says so.
    var isPaused = false

    var isEmpty: Bool { items.isEmpty }
}

/// How the reply that was running ended.
enum ReplyEnd: Equatable, Sendable {
    case finished, failed, stopped
}

/// What to do with the queue now: its new state, and the message to send, if any.
struct QueueStep: Equatable, Sendable {
    var queue: MessageQueue
    var next: QueueItem?
}

/// The rules of the message queue, with no UI and no storage.
enum QueueLogic {
    static func enqueue(_ queue: MessageQueue, _ item: QueueItem) -> MessageQueue {
        var result = queue
        result.items.append(item)
        return result
    }

    static func remove(_ queue: MessageQueue, id: QueueItem.ID) -> MessageQueue {
        var result = queue
        result.items.removeAll { $0.id == id }
        return settled(result)
    }

    /// New text for a queued message. Text cut down to nothing, with no file to send, removes the message.
    static func edit(_ queue: MessageQueue, id: QueueItem.ID, text: String) -> MessageQueue {
        var result = queue
        guard let index = result.items.firstIndex(where: { $0.id == id }) else { return queue }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty && result.items[index].attachments.isEmpty { return remove(queue, id: id) }
        result.items[index].text = trimmed
        return result
    }

    /// A reply ended. A finished one sends the next message; a failed or stopped one holds the queue.
    static func finish(_ queue: MessageQueue, _ end: ReplyEnd) -> QueueStep {
        end == .finished ? next(queue) : QueueStep(queue: pause(queue), next: nil)
    }

    /// The first message goes out, unless the queue is paused or empty.
    static func next(_ queue: MessageQueue) -> QueueStep {
        guard !queue.isPaused, !queue.isEmpty else { return QueueStep(queue: queue, next: nil) }
        var result = queue
        let first = result.items.removeFirst()
        return QueueStep(queue: result, next: first)
    }

    static func pause(_ queue: MessageQueue) -> MessageQueue {
        var result = queue
        result.isPaused = !queue.isEmpty
        return result
    }

    /// "Send queued": lifts the pause and sends the first message.
    static func resume(_ queue: MessageQueue) -> QueueStep {
        var result = queue
        result.isPaused = false
        return next(result)
    }

    /// "Send now": this message goes first, and the rest follow it in order.
    static func sendNow(_ queue: MessageQueue, id: QueueItem.ID) -> QueueStep {
        guard let index = queue.items.firstIndex(where: { $0.id == id }) else { return QueueStep(queue: queue, next: nil) }
        var result = queue
        let item = result.items.remove(at: index)
        result.isPaused = false
        return QueueStep(queue: settled(result), next: item)
    }

    /// A message that could not start goes back to the front, and the queue waits.
    static func requeue(_ queue: MessageQueue, _ item: QueueItem) -> MessageQueue {
        var result = queue
        result.items.insert(item, at: 0)
        result.isPaused = true
        return result
    }

    /// The text of the button that sends a held queue: "Send queued (2)".
    static func resumeTitle(count: Int) -> String { "Send queued (\(count))" }

    /// An empty queue is never paused.
    private static func settled(_ queue: MessageQueue) -> MessageQueue {
        var result = queue
        if result.isEmpty { result.isPaused = false }
        return result
    }
}
