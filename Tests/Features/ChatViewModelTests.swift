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
    }

    private func rig(_ engine: ScriptedEngine, withModel: Bool = true) async throws -> Rig {
        let context = ModelContext(try ModelContainer.anyRouter(inMemory: true))
        let registry = EngineRegistry()
        registry.register(engine)
        let models = ModelStore(registry: registry, defaults: testDefaults())
        if withModel { await models.refresh() }
        let vm = ChatViewModel(thread: nil, context: context, registry: registry,
                               settings: AppSettings(defaults: testDefaults()), models: models)
        return Rig(vm: vm, engine: engine, context: context)
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
}
