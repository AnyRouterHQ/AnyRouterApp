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

    @Test func aRunTheAppWasInIsInterruptedAfterARelaunchButAWaitingRunKeepsWaiting() {
        #expect(AgentRunLogic.afterRelaunch(.running) == .interrupted)
        #expect(AgentRunLogic.afterRelaunch(.awaitingApproval) == .awaitingApproval, "its approval card comes back")
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

/// The resume rules of agent design 1.3, step by step.
struct AgentResumeRuleTests {
    private func step(_ id: String, approval: ToolDecision? = nil, result: String? = nil) -> ToolStep {
        let call = ToolCall(id: id, name: "send_\(id)", argumentsJSON: "{}")
        return ToolStep(call: call, result: result.map { ToolResult(callID: id, name: call.name, text: $0, isError: false) }, approval: approval)
    }

    @Test func anApprovedWriteWithNoResultIsNeverRunAgainAndSaysSo() {
        let steps = [
            step("write", approval: .allowOnce), step("external", approval: .alwaysAllow), step("unknown", approval: .allowOnce),
            step("read", approval: .allowOnce), step("denied", approval: .deny), step("done", approval: .allowOnce, result: "sent"),
            step("waiting"),
        ]
        let effects: [String: ToolSideEffect] = ["write": .write, "external": .external, "read": .read, "denied": .write, "done": .write]
        let settled = AgentRunLogic.settled(steps, sideEffects: effects)
        #expect(settled[0].result == ToolResult(callID: "write", name: "send_write", text: ToolRowLogic.unfinishedText, isError: true))
        #expect(settled[1].result?.text == ToolRowLogic.unfinishedText)
        #expect(settled[2].result?.text == ToolRowLogic.unfinishedText, "a call whose class is unknown counts as a write")
        #expect(settled[3] == steps[3], "an approved read runs again instead")
        #expect(settled[4] == steps[4] && settled[5] == steps[5] && settled[6] == steps[6])
        #expect(ToolRowLogic.title(for: settled[0]) == "Used send_write may not have finished")
    }

    @Test func approvedCallsWithNoResultRunWithoutAskingAgain() {
        let steps = [step("a", approval: .allowOnce), step("b", approval: .deny), step("c", approval: .alwaysAllow, result: "ok"), step("d")]
        #expect(AgentRunLogic.decided(steps) == ["a": .allowOnce])
    }

    @Test func aStepIsAddedOnceAndAnAnswerLandsOnItsStep() {
        let first = step("a")
        #expect(AgentRunLogic.adding(first, to: []) == [first])
        let answered = AgentRunLogic.approving(first.call, .allowOnce, in: [first])
        #expect(answered.count == 1 && answered[0].approval == .allowOnce)
        #expect(AgentRunLogic.adding(first, to: answered) == answered, "the resumed run announces the call again")
        let early = AgentRunLogic.approving(first.call, .deny, in: [])
        #expect(early == [ToolStep(call: first.call, result: nil, approval: .deny)], "the answer came before the row")
    }

    @Test func aStepSavedBeforeApprovalsExistedStillReads() throws {
        let old = Data(#"{"call":{"id":"c1","name":"web_search","argumentsJSON":"{}"},"sourceID":"device"}"#.utf8)
        let decoded = try JSONDecoder().decode(ToolStep.self, from: old)
        #expect(decoded.approval == nil && decoded.result == nil && decoded.sourceID == "device")
        let answered = ToolStep(call: decoded.call, result: nil, approval: .allowOnce)
        #expect(try JSONDecoder().decode(ToolStep.self, from: JSONEncoder().encode(answered)) == answered)
    }

    @Test func theRunStateRoundTripsAndUnreadableDataIsEmpty() {
        let run = AgentRunRecord(threadID: UUID(), messageID: UUID(), modelID: "m")
        #expect(run.stateData == nil && run.state == AgentRunState())
        let state = AgentRunState(
            rounds: [AgentSavedRound(text: "Let me send it.", calls: [ToolCall(id: "c1", name: "send", argumentsJSON: "{}")])],
            sideEffects: ["c1": .external])
        run.state = state
        #expect(run.state == state)
        run.stateData = Data("nope".utf8)
        #expect(run.state == AgentRunState())
    }
}

/// The launch sweep against a saved store: what each kind of unfinished run looks like afterwards.
@MainActor
struct AgentRunSweepTests {
    @Test func aRunningRunIsInterruptedAndItsApprovedWriteSaysItMayNotHaveFinished() throws {
        let context = ModelContext(try ModelContainer.anyRouter(inMemory: true))
        let thread = ThreadRecord()
        let reply = MessageRecord(role: .assistant, content: "")
        context.insert(thread)
        context.insert(reply)
        reply.thread = thread
        let call = ToolCall(id: "c1", name: "send", argumentsJSON: "{}")
        reply.toolSteps = [ToolStep(call: call, result: nil, approval: .allowOnce)]
        let running = AgentRunRecord(threadID: thread.id, messageID: reply.id, modelID: "m")
        running.state = AgentRunState(rounds: [], sideEffects: ["c1": .write])
        let waiting = AgentRunRecord(threadID: thread.id, messageID: UUID(), modelID: "m")
        waiting.status = .awaitingApproval
        let orphan = AgentRunRecord(threadID: thread.id, messageID: UUID(), modelID: "m")
        let done = AgentRunRecord(threadID: thread.id, messageID: reply.id, modelID: "m")
        done.status = .interrupted
        for run in [running, waiting, orphan, done] { context.insert(run) }
        try context.save()

        AgentRunSweep.run(context)

        #expect(running.status == .interrupted && orphan.status == .interrupted)
        #expect(waiting.status == .awaitingApproval, "its chat brings the card back")
        #expect(reply.toolSteps.first?.result?.text == ToolRowLogic.unfinishedText)
        #expect(ToolRowLogic.status(of: reply.toolSteps[0]) == .failed)
    }
}
