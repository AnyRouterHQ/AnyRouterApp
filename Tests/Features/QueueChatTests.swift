import Foundation
import SwiftData
import Testing
@testable import AnyRouter

@MainActor
struct QueueChatTests {
    private struct Rig {
        let vm: ChatViewModel
        let engine: ScriptedEngine
    }

    private func rig(_ engine: ScriptedEngine, online: Bool = true, withModel: Bool = true,
                     thread: ThreadRecord? = nil) async throws -> Rig {
        let context = ModelContext(try ModelContainer.anyRouter(inMemory: true))
        let registry = EngineRegistry()
        registry.register(engine)
        let models = ModelStore(registry: registry, defaults: testDefaults())
        if withModel { await models.refresh() }
        let vm = ChatViewModel(thread: thread, context: context, registry: registry,
                               settings: AppSettings(defaults: testDefaults()), models: models, isOnline: { online })
        return Rig(vm: vm, engine: engine)
    }

    private func numbered() -> ScriptedEngine {
        var engine = ScriptedEngine()
        engine.numberedReplies = true
        return engine
    }

    private func contents(_ vm: ChatViewModel) -> [String] { vm.messages.map(\.content) }

    private func queueTexts(_ vm: ChatViewModel) -> [String] { vm.queue.items.map(\.text) }

    private func start(_ vm: ChatViewModel, _ text: String) -> Task<Void, Never>? {
        vm.input = text
        return vm.send()
    }

    private func enqueue(_ vm: ChatViewModel, _ text: String) {
        vm.input = text
        vm.enqueue()
    }

    @Test func nothingIsQueuedWhileIdle() async throws {
        let r = try await rig(numbered())
        r.vm.input = "hi"
        #expect(!r.vm.canQueue)
        r.vm.enqueue()
        #expect(r.vm.input == "hi")
        #expect(r.vm.queue.isEmpty)
    }

    @Test func messagesTypedDuringAReplyGoOutInOrderWhenItEnds() async throws {
        let r = try await rig(numbered())
        _ = try #require(start(r.vm, "one"))
        #expect(r.vm.canSend == false)
        r.vm.input = "two"
        #expect(r.vm.canQueue)
        r.vm.enqueue()
        enqueue(r.vm, "three")
        #expect(r.vm.input.isEmpty)
        #expect(queueTexts(r.vm) == ["two", "three"])
        #expect(await waitUntil { contents(r.vm) == ["one", "reply 1", "two", "reply 2", "three", "reply 3"] && r.vm.phase == .idle })
        #expect(r.vm.queue.isEmpty)
        #expect(r.vm.messages.map(\.role) == [.user, .assistant, .user, .assistant, .user, .assistant])
    }

    @Test func theQueueIsStoredWithTheThread() async throws {
        let r = try await rig(ScriptedEngine(chunks: ["partial"], hangs: true))
        let task = try #require(start(r.vm, "one"))
        enqueue(r.vm, "later")
        #expect(r.vm.thread?.queue.items.map(\.text) == ["later"])
        r.vm.stop()
        await task.value
    }

    @Test func stoppingPausesTheQueueUntilSendQueued() async throws {
        let r = try await rig(ScriptedEngine(chunks: ["partial"], hangs: true))
        let task = try #require(start(r.vm, "one"))
        enqueue(r.vm, "two")
        r.vm.stop()
        await task.value
        #expect(r.vm.phase == .idle)
        #expect(r.vm.queue.isPaused)
        #expect(r.vm.queueIsHeld)
        let nextCall = r.engine.calls.next()
        #expect(nextCall == 2, "only the first reply was requested")
        r.vm.resumeQueue()
        #expect(r.vm.phase == .streaming)
        #expect(r.vm.messages.map(\.content).contains("two"))
        #expect(r.vm.queue.isEmpty)
        r.vm.stop()
    }

    @Test func aFailedReplyPausesTheQueue() async throws {
        var engine = ScriptedEngine()
        engine.failure = "boom"
        let r = try await rig(engine)
        let task = try #require(start(r.vm, "one"))
        enqueue(r.vm, "two")
        await task.value
        #expect(r.vm.phase == .idle)
        #expect(r.vm.queue.isPaused)
        #expect(queueTexts(r.vm) == ["two"])
    }

    @Test func sendQueuedDoesNothingWhileAReplyRuns() async throws {
        let r = try await rig(ScriptedEngine(chunks: ["partial"], hangs: true))
        let task = try #require(start(r.vm, "one"))
        enqueue(r.vm, "two")
        r.vm.resumeQueue()
        #expect(queueTexts(r.vm) == ["two"])
        r.vm.stop()
        await task.value
    }

    @Test func sendNowStopsTheReplyAndSendsThatMessageFirst() async throws {
        let r = try await rig(ScriptedEngine(chunks: ["partial"], hangs: true))
        let task = try #require(start(r.vm, "one"))
        enqueue(r.vm, "a")
        enqueue(r.vm, "b")
        let b = r.vm.queue.items[1].id
        r.vm.sendQueuedNow(b)
        await task.value
        #expect(r.vm.messages.filter { $0.role == .user }.map(\.content) == ["one", "b"])
        #expect(queueTexts(r.vm) == ["a"])
        #expect(!r.vm.queue.isPaused, "the rest follow in order")
        r.vm.stop()
    }

    @Test func sendNowOfAMessageThatIsGoneDoesNothing() async throws {
        let r = try await rig(ScriptedEngine(chunks: ["partial"], hangs: true))
        let task = try #require(start(r.vm, "one"))
        enqueue(r.vm, "a")
        r.vm.sendQueuedNow(UUID())
        #expect(r.vm.phase == .streaming)
        #expect(queueTexts(r.vm) == ["a"])
        r.vm.stop()
        await task.value
    }

    @Test func sendNowOnAHeldQueueSendsAtOnce() async throws {
        let r = try await rig(ScriptedEngine(chunks: ["partial"], hangs: true))
        let task = try #require(start(r.vm, "one"))
        enqueue(r.vm, "a")
        enqueue(r.vm, "b")
        r.vm.stop()
        await task.value
        r.vm.sendQueuedNow(r.vm.queue.items[1].id)
        #expect(r.vm.phase == .streaming)
        #expect(r.vm.messages.filter { $0.role == .user }.map(\.content) == ["one", "b"])
        #expect(queueTexts(r.vm) == ["a"])
        r.vm.stop()
    }

    @Test func removingAndEditingChangeTheStoredQueue() async throws {
        let r = try await rig(ScriptedEngine(chunks: ["partial"], hangs: true))
        let task = try #require(start(r.vm, "one"))
        enqueue(r.vm, "a")
        enqueue(r.vm, "b")
        r.vm.editQueued(r.vm.queue.items[0].id, text: "a2")
        r.vm.removeQueued(r.vm.queue.items[1].id)
        #expect(queueTexts(r.vm) == ["a2"])
        r.vm.stop()
        await task.value
    }

    @Test func nothingGoesOutInTheBackgroundAndItGoesWhenTheAppIsActiveAgain() async throws {
        let r = try await rig(numbered())
        r.vm.setForeground(true)
        r.vm.setForeground(false)
        let task = try #require(start(r.vm, "one"))
        enqueue(r.vm, "two")
        await task.value
        #expect(r.vm.phase == .idle)
        #expect(queueTexts(r.vm) == ["two"])
        #expect(contents(r.vm) == ["one", "reply 1"])
        r.vm.setForeground(true)
        #expect(await waitUntil { contents(r.vm) == ["one", "reply 1", "two", "reply 2"] && r.vm.phase == .idle })
        #expect(r.vm.queue.isEmpty)
    }

    @Test func aFailureInTheBackgroundStillPausesTheQueue() async throws {
        var engine = ScriptedEngine()
        engine.failure = "boom"
        let r = try await rig(engine)
        r.vm.setForeground(false)
        let task = try #require(start(r.vm, "one"))
        enqueue(r.vm, "two")
        await task.value
        r.vm.setForeground(true)
        #expect(r.vm.queue.isPaused)
        #expect(contents(r.vm).count == 2)
    }

    @Test func comingBackWithNothingWaitingSendsNothing() async throws {
        let r = try await rig(numbered())
        let task = try #require(start(r.vm, "one"))
        await task.value
        r.vm.setForeground(false)
        r.vm.setForeground(true)
        #expect(contents(r.vm) == ["one", "reply 1"])
    }

    @Test func aMessageThatCannotStartStaysAtTheFrontOfAHeldQueue() async throws {
        let r = try await rig(numbered(), withModel: false, thread: ThreadRecord())
        r.vm.storeQueue(MessageQueue(items: [QueueItem(text: "one")]))
        r.vm.resumeQueue()
        #expect(r.vm.errorMessage == "Choose a model first.")
        #expect(queueTexts(r.vm) == ["one"])
        #expect(r.vm.queue.isPaused)
    }

    @Test func aCloudMessageOfflineStaysQueuedToo() async throws {
        var engine = ScriptedEngine(source: .anyrouter, models: [testModel(id: "anyrouter/auto", source: .anyrouter)])
        engine.numberedReplies = true
        let r = try await rig(engine, online: false, thread: ThreadRecord())
        r.vm.storeQueue(MessageQueue(items: [QueueItem(text: "one")]))
        r.vm.resumeQueue()
        #expect(r.vm.errorMessage != nil)
        #expect(queueTexts(r.vm) == ["one"])
        #expect(r.vm.queue.isPaused)
        #expect(r.vm.phase == .idle)
    }
}
