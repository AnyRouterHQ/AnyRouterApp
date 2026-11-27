import Foundation
import Testing
@testable import AnyRouter

struct QueueLogicTests {
    private func item(_ text: String, files: [ChatAttachment] = []) -> QueueItem { QueueItem(text: text, attachments: files) }

    private func queue(_ texts: String..., paused: Bool = false) -> MessageQueue {
        MessageQueue(items: texts.map { item($0) }, isPaused: paused)
    }

    private func file() -> ChatAttachment {
        ChatAttachment(id: UUID(), kind: .text, filename: "a.txt", utType: "public.plain-text", byteCount: 1, relativePath: "t/a.txt")
    }

    @Test func messagesQueueInTheOrderTheyWereTyped() {
        let result = QueueLogic.enqueue(QueueLogic.enqueue(MessageQueue(), item("one")), item("two"))
        #expect(result.items.map(\.text) == ["one", "two"])
        #expect(!result.isPaused)
    }

    @Test func removingTheLastMessageLeavesNothingPaused() {
        let held = queue("one", paused: true)
        let result = QueueLogic.remove(held, id: held.items[0].id)
        #expect(result.isEmpty)
        #expect(!result.isPaused)
    }

    @Test func removingOneKeepsTheRestAndThePause() {
        let held = queue("one", "two", paused: true)
        let result = QueueLogic.remove(held, id: held.items[0].id)
        #expect(result.items.map(\.text) == ["two"])
        #expect(result.isPaused)
    }

    @Test func editingReplacesTheTextWithoutMovingTheMessage() {
        let start = queue("one", "two")
        let result = QueueLogic.edit(start, id: start.items[1].id, text: "  second  ")
        #expect(result.items.map(\.text) == ["one", "second"])
        #expect(result.items[1].id == start.items[1].id)
    }

    @Test func editingToNothingRemovesAMessageWithoutFiles() {
        let start = queue("one", "two")
        let result = QueueLogic.edit(start, id: start.items[0].id, text: "   ")
        #expect(result.items.map(\.text) == ["two"])
    }

    @Test func editingToNothingKeepsAMessageThatCarriesAFile() {
        let start = MessageQueue(items: [item("one", files: [file()])])
        let result = QueueLogic.edit(start, id: start.items[0].id, text: "")
        #expect(result.items.count == 1)
        #expect(result.items[0].text.isEmpty)
    }

    @Test func editingAMessageThatIsGoneChangesNothing() {
        let start = queue("one")
        #expect(QueueLogic.edit(start, id: UUID(), text: "x") == start)
    }

    @Test func aFinishedReplySendsTheFirstMessageAndKeepsTheRest() {
        let step = QueueLogic.finish(queue("one", "two"), .finished)
        #expect(step.next?.text == "one")
        #expect(step.queue.items.map(\.text) == ["two"])
        #expect(!step.queue.isPaused)
    }

    @Test func aFinishedReplyWithAnEmptyQueueSendsNothing() {
        let step = QueueLogic.finish(MessageQueue(), .finished)
        #expect(step.next == nil)
        #expect(step.queue.isEmpty)
    }

    @Test func aPausedQueueSendsNothingEvenAfterAFinishedReply() {
        let held = queue("one", paused: true)
        let step = QueueLogic.finish(held, .finished)
        #expect(step.next == nil)
        #expect(step.queue == held)
    }

    @Test func aFailedOrStoppedReplyPausesTheQueue() {
        for end in [ReplyEnd.failed, .stopped] {
            let step = QueueLogic.finish(queue("one", "two"), end)
            #expect(step.next == nil)
            #expect(step.queue.isPaused)
            #expect(step.queue.items.count == 2)
        }
    }

    @Test func aFailedReplyWithNothingQueuedPausesNothing() {
        #expect(!QueueLogic.finish(MessageQueue(), .failed).queue.isPaused)
    }

    @Test func sendQueuedLiftsThePauseAndSendsTheFirst() {
        let step = QueueLogic.resume(queue("one", "two", paused: true))
        #expect(step.next?.text == "one")
        #expect(step.queue.items.map(\.text) == ["two"])
        #expect(!step.queue.isPaused)
    }

    @Test func sendNowTakesThatMessageOutOfOrderAndUnpauses() {
        let held = queue("one", "two", "three", paused: true)
        let step = QueueLogic.sendNow(held, id: held.items[1].id)
        #expect(step.next?.text == "two")
        #expect(step.queue.items.map(\.text) == ["one", "three"])
        #expect(!step.queue.isPaused)
    }

    @Test func sendNowOfAMessageThatIsGoneChangesNothing() {
        let start = queue("one", paused: true)
        let step = QueueLogic.sendNow(start, id: UUID())
        #expect(step.next == nil)
        #expect(step.queue == start)
    }

    @Test func aMessageThatCouldNotStartGoesBackToTheFrontAndTheQueueWaits() {
        let result = QueueLogic.requeue(queue("two"), item("one"))
        #expect(result.items.map(\.text) == ["one", "two"])
        #expect(result.isPaused)
    }

    @Test func theResumeButtonCountsWhatWaits() {
        #expect(QueueLogic.resumeTitle(count: 2) == "Send queued (2)")
    }
}

struct QueueRecordTests {
    @Test func aChatStoredBeforeQueuesHasAnEmptyQueue() {
        let thread = ThreadRecord()
        #expect(thread.queueData == nil)
        #expect(thread.queue == MessageQueue())
    }

    @Test func aThreadKeepsItsQueueAsJSON() {
        let thread = ThreadRecord()
        let held = MessageQueue(items: [QueueItem(text: "later")], isPaused: true)
        thread.queue = held
        #expect(thread.queue == held)
        thread.queue = MessageQueue()
        #expect(thread.queueData == nil)
    }

    @Test func unreadableDataReadsAsAnEmptyQueue() {
        let thread = ThreadRecord()
        thread.queueData = Data("nope".utf8)
        #expect(thread.queue.isEmpty)
    }
}
