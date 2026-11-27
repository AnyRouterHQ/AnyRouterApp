import Foundation
import SwiftData
import Testing
@testable import AnyRouter

struct AgentRunLogicTests {
    private let start = AgentRunLogic.Checkpoint(node: .generate, round: 0)
    private let call = ToolCall(id: "c1", name: "web_search", argumentsJSON: "{}")

    @Test func aCallStartsActAndItsResultEndsTheRound() {
        let acting = AgentRunLogic.checkpoint(after: .toolCall(call), from: start)
        #expect(acting == AgentRunLogic.Checkpoint(node: .act, round: 0))
        #expect(AgentRunLogic.checkpoint(after: .toolCall(call), from: AgentRunLogic.Checkpoint(node: .act, round: 0)) == nil, "a second call in the same round")
        let result = ToolResult(callID: "c1", name: "web_search", text: "ok", isError: false)
        #expect(AgentRunLogic.checkpoint(after: .toolResult(result), from: AgentRunLogic.Checkpoint(node: .act, round: 0)) == AgentRunLogic.Checkpoint(node: .generate, round: 1))
        #expect(AgentRunLogic.checkpoint(after: .toolResult(result), from: AgentRunLogic.Checkpoint(node: .generate, round: 1)) == nil, "a second result")
        #expect(AgentRunLogic.checkpoint(after: .text("hi"), from: start) == nil, "text is never a boundary")
    }

    @Test func aRunTheAppWasInIsInterruptedAfterARelaunch() {
        #expect(AgentRunLogic.afterRelaunch(.running) == .interrupted)
        #expect(AgentRunLogic.afterRelaunch(.awaitingApproval) == .interrupted)
        #expect(AgentRunLogic.afterRelaunch(.finished) == .finished)
    }

    @Test func anUnknownStatusOrNodeIsNeverResumed() {
        let run = AgentRunRecord(threadID: UUID(), messageID: UUID(), modelID: "apple/foundation")
        #expect(run.status == .running && run.node == .assemble && run.round == 0)
        run.status = .awaitingApproval
        run.node = .approve
        #expect(run.statusRaw == "awaitingApproval" && run.nodeRaw == "approve")
        run.statusRaw = "paused"
        run.nodeRaw = "plan"
        #expect(run.status == .interrupted)
        #expect(run.node == .finish)
    }
}

/// A run is saved at its step boundaries; a kill leaves it where it stopped, and the next launch marks it interrupted.
@MainActor
struct AgentRunChatTests {
    private let call = ToolCall(id: "c1", name: "web_search", argumentsJSON: #"{"query":"swift"}"#)

    private func start(_ deltas: [ChatDelta]) async throws -> (vm: ChatViewModel, context: ModelContext, task: Task<Void, Never>) {
        let registry = EngineRegistry()
        registry.register(ScriptedEngine(chunks: [], hangs: true, deltas: deltas))
        let models = ModelStore(registry: registry, defaults: testDefaults())
        await models.refresh()
        let context = ModelContext(try ModelContainer.anyRouter(inMemory: true))
        let vm = ChatViewModel(thread: nil, context: context, registry: registry, settings: AppSettings(defaults: testDefaults()), models: models)
        vm.input = "news?"
        let task = try #require(vm.send())
        return (vm, context, task)
    }

    private func runs(_ context: ModelContext) throws -> [AgentRunRecord] {
        try context.fetch(FetchDescriptor<AgentRunRecord>())
    }

    @Test func killedWhileItsToolRunsTheRunIsAtAct() async throws {
        let r = try await start([.toolCall(call)])
        #expect(await waitUntil { (try? runs(r.context).first?.node) == .act })
        let run = try #require(try runs(r.context).first)
        #expect(run.status == .running && run.round == 0 && run.messageID == r.vm.messages.last?.id && run.threadID == r.vm.thread?.id)
        r.vm.stop()
        await r.task.value
        #expect(try runs(r.context).isEmpty, "a run that ends is deleted")
    }

    @Test func killedAfterAResultTheRunIsBackAtGenerateAndTheNextLaunchMarksItInterrupted() async throws {
        let result = ToolResult(callID: "c1", name: "web_search", text: "Swift 7", isError: false)
        let r = try await start([.toolCall(call), .toolResult(result)])
        #expect(await waitUntil { (try? runs(r.context).first?.round) == 1 })
        #expect(try runs(r.context).first?.node == .generate)
        AgentRunSweep.run(r.context)
        #expect(try runs(r.context).first?.status == .interrupted)
        r.vm.stop()
        await r.task.value
    }
}
