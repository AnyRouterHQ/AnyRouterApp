import Foundation

/// Queue mode: messages typed while a reply streams wait in the thread and go out one by one when it ends.
extension ChatViewModel {
    var queue: MessageQueue { thread?.queue ?? MessageQueue() }

    /// Nothing is running and messages still wait: the queue is held, and "Send queued" sends it.
    var queueIsHeld: Bool { phase == .idle && !queue.isEmpty }

    func removeQueued(_ id: QueueItem.ID) { storeQueue(QueueLogic.remove(queue, id: id)) }

    func editQueued(_ id: QueueItem.ID, text: String) { storeQueue(QueueLogic.edit(queue, id: id, text: text)) }

    func resumeQueue() {
        guard phase == .idle else { return }
        apply(QueueLogic.resume(queue))
    }

    /// Stops the reply that is running and sends this message next; the rest follow it.
    func sendQueuedNow(_ id: QueueItem.ID) {
        let step = QueueLogic.sendNow(queue, id: id)
        guard let item = step.next else { return }
        storeQueue(step.queue)
        if phase == .idle {
            launch(item)
        } else {
            promotedItem = item
            stop()
        }
    }

    /// The app became active or left it. A queued send that waited for the foreground goes out now.
    func setForeground(_ active: Bool) {
        isForeground = active
        guard active, sendsWhenActive, phase == .idle else { return }
        sendsWhenActive = false
        apply(QueueLogic.next(queue))
    }

    /// Called when a reply has ended and the chat is idle again.
    func queueReplyEnded(failure: ReplyFailure?) {
        sendsWhenActive = false
        if let item = promotedItem {
            promotedItem = nil
            launch(item)
            return
        }
        guard !queue.isEmpty else { return }
        let end: ReplyEnd = failure != nil ? .failed : (Task.isCancelled ? .stopped : .finished)
        if end == .finished && !isForeground {
            sendsWhenActive = true
            return
        }
        apply(QueueLogic.finish(queue, end))
    }

    private func apply(_ step: QueueStep) {
        storeQueue(step.queue)
        if let next = step.next { launch(next) }
    }

    private func launch(_ item: QueueItem) {
        if !sendQueued(item) { storeQueue(QueueLogic.requeue(queue, item)) }
    }
}
