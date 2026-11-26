import Foundation
import SwiftData
import Testing
@testable import AnyRouter

@MainActor
struct ChatViewModelTests {
    private struct Rig {
        let vm: ChatViewModel
        let engine: ScriptedEngine
        let context: ModelContext
        let registry: EngineRegistry
        let models: ModelStore

        /// A second view model on the same thread, as when the thread is opened again.
        @MainActor func reopen() -> ChatViewModel {
            ChatViewModel(thread: vm.thread, context: context, registry: registry,
                          settings: AppSettings(defaults: testDefaults()), models: models)
        }
    }

    private func rig(_ engine: ScriptedEngine, withModel: Bool = true) async throws -> Rig {
        let context = ModelContext(try ModelContainer.anyRouter(inMemory: true))
        let registry = EngineRegistry()
        registry.register(engine)
        let models = ModelStore(registry: registry, defaults: testDefaults())
        if withModel { await models.refresh() }
        let vm = ChatViewModel(thread: nil, context: context, registry: registry,
                               settings: AppSettings(defaults: testDefaults()), models: models)
        return Rig(vm: vm, engine: engine, context: context, registry: registry, models: models)
    }

    private func twoModels() -> ScriptedEngine {
        var engine = ScriptedEngine(models: [testModel(id: "a"), testModel(id: "b")])
        engine.numberedReplies = true
        return engine
    }

    @Test func sendStreamsReplyIntoNewThread() async throws {
        let r = try await rig(ScriptedEngine(chunks: ["Hel", "lo"]))
        var created: UUID?
        r.vm.onThreadCreated = { created = $0 }
        r.vm.input = "Hi there"
        await r.vm.send()?.value
        #expect(r.vm.messages.map(\.role) == [.user, .assistant])
        #expect(r.vm.messages.last?.content == "Hello")
        #expect(r.vm.thread?.title == "Hi there")
        #expect(created == r.vm.thread?.id)
        #expect(r.vm.phase == .idle)
        #expect(r.vm.input.isEmpty)
    }

    @Test func blankInputDoesNotSend() async throws {
        let r = try await rig(ScriptedEngine(chunks: ["x"]))
        r.vm.input = "   "
        #expect(r.vm.send() == nil)
        #expect(r.vm.thread == nil)
    }

    @Test func sendWithoutModelReportsErrorAndKeepsInput() async throws {
        let r = try await rig(ScriptedEngine(), withModel: false)
        r.vm.input = "Hi"
        #expect(r.vm.send() == nil)
        #expect(r.vm.errorMessage != nil)
        #expect(r.vm.input == "Hi")
    }

    @Test func stopCancelsEngineAndKeepsPartialReply() async throws {
        let r = try await rig(ScriptedEngine(chunks: ["partial"], hangs: true))
        r.vm.input = "Hi"
        let task = try #require(r.vm.send())
        #expect(await waitUntil { r.vm.messages.last?.content == "partial" })
        #expect(r.vm.isStreaming)
        r.vm.stop()
        await task.value
        #expect(r.vm.phase == .idle)
        #expect(r.vm.messages.last?.content == "partial")
        #expect(await waitUntil { r.engine.terminated.value })
    }

    @Test func stopBeforeFirstTokenRemovesEmptyReply() async throws {
        let r = try await rig(ScriptedEngine(hangs: true))
        r.vm.input = "Hi"
        let task = try #require(r.vm.send())
        #expect(r.vm.isStreaming)
        r.vm.stop()
        await task.value
        #expect(r.vm.messages.map(\.role) == [.user])
        #expect(r.vm.phase == .idle)
    }

    @Test func engineFailureKeepsPartialAndShowsError() async throws {
        let r = try await rig(ScriptedEngine(chunks: ["half"], failure: "boom"))
        r.vm.input = "Hi"
        await r.vm.send()?.value
        #expect(r.vm.messages.last?.content == "half")
        #expect(r.vm.errorMessage == "boom")
        #expect(r.vm.phase == .idle)
    }

    @Test func cannotSendWhileStreaming() async throws {
        let r = try await rig(ScriptedEngine(chunks: ["a"], hangs: true))
        r.vm.input = "one"
        let task = try #require(r.vm.send())
        r.vm.input = "two"
        #expect(!r.vm.canSend)
        #expect(r.vm.send() == nil)
        r.vm.stop()
        await task.value
    }

    @Test func regenerateReplacesLastReply() async throws {
        var engine = ScriptedEngine()
        engine.numberedReplies = true
        let r = try await rig(engine)
        r.vm.input = "Hi"
        await r.vm.send()?.value
        #expect(r.vm.messages.last?.content == "reply 1")
        await r.vm.regenerate()?.value
        #expect(r.vm.messages.map(\.role) == [.user, .assistant])
        #expect(r.vm.messages.last?.content == "reply 2")
    }

    // MARK: - Pick and change model

    @Test func switchingMidThreadKeepsHistoryAndTheNextReplyUsesTheNewModel() async throws {
        let r = try await rig(twoModels())
        r.vm.input = "one"
        await r.vm.send()?.value
        #expect(r.vm.model?.id == "a")
        r.vm.choose(testModel(id: "b"))
        r.vm.input = "two"
        await r.vm.send()?.value
        #expect(r.engine.usedModels.values == ["a", "b"])
        #expect(r.vm.messages.map(\.content) == ["one", "reply 1", "two", "reply 2"])
        #expect(r.vm.thread?.modelID == "b")
    }

    @Test func eachReplyShowsTheModelThatWroteIt() async throws {
        let r = try await rig(twoModels())
        r.vm.input = "one"
        await r.vm.send()?.value
        r.vm.choose(testModel(id: "b"))
        r.vm.input = "two"
        await r.vm.send()?.value
        let names = r.vm.messages.filter { $0.role == .assistant }.map(\.modelName)
        #expect(names == ["a", "b"])
    }

    @Test func aPickBeforeTheFirstMessageIsSavedOnTheNewThread() async throws {
        let r = try await rig(twoModels())
        r.vm.choose(testModel(id: "b"))
        r.vm.input = "hi"
        await r.vm.send()?.value
        #expect(r.engine.usedModels.values == ["b"])
        #expect(r.vm.thread?.modelID == "b")
    }

    @Test func aPickBecomesTheDefaultForNewChatsButNotForOtherThreads() async throws {
        let r = try await rig(twoModels())
        r.vm.input = "first"
        await r.vm.send()?.value // thread 1 uses a
        let other = ChatViewModel(thread: nil, context: r.context, registry: r.registry,
                                  settings: AppSettings(defaults: testDefaults()), models: r.models)
        other.choose(testModel(id: "b"))
        #expect(r.models.selected?.id == "b")
        let fresh = ChatViewModel(thread: nil, context: r.context, registry: r.registry,
                                  settings: AppSettings(defaults: testDefaults()), models: r.models)
        #expect(fresh.model?.id == "b")
        #expect(r.vm.model?.id == "a")
        #expect(r.reopen().model?.id == "a")
    }

    @Test func reopeningAThreadRestoresItsModelEvenWhenTheDefaultMovedOn() async throws {
        let r = try await rig(twoModels())
        r.vm.choose(testModel(id: "b"))
        r.vm.input = "hi"
        await r.vm.send()?.value
        r.models.select(testModel(id: "a"))
        #expect(r.reopen().model?.id == "b")
    }

    @Test func switchingModelDuringAStreamKeepsThatStreamOnTheOldModel() async throws {
        var engine = twoModels()
        engine.chunks = ["partial"]
        engine.numberedReplies = false
        engine.hangs = true
        let r = try await rig(engine)
        r.vm.input = "hi"
        let task = try #require(r.vm.send())
        r.vm.choose(testModel(id: "b"))
        r.vm.stop()
        await task.value
        #expect(r.engine.usedModels.values == ["a"])
        #expect(r.vm.model?.id == "b")
    }

    @Test func regenerateAfterSwitchingUsesTheNewModel() async throws {
        let r = try await rig(twoModels())
        r.vm.input = "hi"
        await r.vm.send()?.value
        r.vm.choose(testModel(id: "b"))
        await r.vm.regenerate()?.value
        #expect(r.engine.usedModels.values == ["a", "b"])
        #expect(r.vm.messages.last?.modelName == "b")
    }

    // MARK: - Fallback notice

    private func threadWithModel(_ id: String, in r: Rig) -> ChatViewModel {
        let thread = ThreadRecord(title: "Old", modelID: id)
        r.context.insert(thread)
        return ChatViewModel(thread: thread, context: r.context, registry: r.registry,
                             settings: AppSettings(defaults: testDefaults()), models: r.models)
    }

    @Test func anUnusableThreadModelFallsBackToTheDefaultWithOneLineNotice() async throws {
        let r = try await rig(twoModels())
        let vm = threadWithModel("gone/model", in: r)
        #expect(vm.model?.id == "a")
        let notice = try #require(vm.modelNotice)
        #expect(notice.hasSuffix("Using a."))
        #expect(!notice.contains("\n"))
    }

    @Test func noNoticeForAUsableModelANewChatOrBeforeModelsLoad() async throws {
        let r = try await rig(twoModels())
        #expect(threadWithModel("b", in: r).modelNotice == nil)
        #expect(r.vm.modelNotice == nil)
        let unloaded = try await rig(twoModels(), withModel: false)
        #expect(threadWithModel("b", in: unloaded).modelNotice == nil)
    }

    @Test func pickingAModelClearsTheNoticeAndSendingAlsoDoes() async throws {
        let r = try await rig(twoModels())
        let sent = threadWithModel("gone/model", in: r)
        sent.input = "hi"
        await sent.send()?.value
        #expect(sent.modelNotice == nil)
        #expect(sent.thread?.modelID == "a")

        let picked = threadWithModel("gone/model", in: r)
        picked.choose(testModel(id: "b"))
        #expect(picked.modelNotice == nil)
        #expect(picked.model?.id == "b")
    }

    @Test func withNothingUsableTheNoticeAsksForAModel() async throws {
        let r = try await rig(ScriptedEngine(models: [testModel(id: "a", installed: false)]))
        let vm = threadWithModel("gone/model", in: r)
        #expect(vm.model == nil)
        #expect(vm.modelNotice?.contains("Choose") == true)
    }
}
