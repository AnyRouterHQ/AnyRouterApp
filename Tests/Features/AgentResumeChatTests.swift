import Foundation
import SwiftData
import Testing
@testable import AnyRouter

/// How many times the tool body itself ran.
private final class RunCount: @unchecked Sendable {
    private let lock = NSLock()
    private var raw = 0
    var value: Int { lock.withLock { raw } }
    func add() { lock.withLock { raw += 1 } }
}

/// A tool that acts outside the app, so it asks every time.
private struct SendNote: BuiltInTool {
    let runs: RunCount
    let name = "send_note"
    let title = "Send note"
    let summary = "Sends a note."
    let description = "Sends a note."
    let inputSchemaJSON = #"{"type":"object"}"#
    let sideEffect = ToolSideEffect.external

    func run(_ arguments: JSONValue) async throws -> String {
        runs.add()
        return "sent"
    }
}

/// One scripted model round per request, keeping the rounds each request carried.
private final class RoundScript: StepFunction, @unchecked Sendable {
    let budget: RunBudgetLogic.Budget? = nil
    private let lock = NSLock()
    private var scripts: [[StepEvent]]
    private var asked: [[AgentRound]] = []

    init(_ scripts: [[StepEvent]]) { self.scripts = scripts }

    var requests: [[AgentRound]] { lock.withLock { asked } }

    func tokens(_ rounds: [AgentRound], toolsOn: Bool) -> Int { 0 }

    func step(_ rounds: [AgentRound], toolsOn: Bool) -> AsyncThrowingStream<StepEvent, Error> {
        let events = lock.withLock { () -> [StepEvent] in
            asked.append(rounds)
            return scripts.isEmpty ? [.end(finishReason: "stop")] : scripts.removeFirst()
        }
        return AsyncThrowingStream { continuation in
            for event in events { continuation.yield(event) }
            continuation.finish()
        }
    }
}

/// An engine on the app's loop, as the AnyRouter and local engines are.
private struct LoopEngine: ResumableEngine {
    let source = ModelSource.apple
    let script: RoundScript

    func availableModels() async throws -> [ModelDescriptor] { [testModelWithTools()] }

    func stream(model: ModelDescriptor, messages: [ChatMessage], params: GenerationParams) -> AsyncThrowingStream<ChatDelta, Error> {
        stream(model: model, messages: messages, params: params, tools: nil, resuming: nil)
    }

    func stream(model: ModelDescriptor, messages: [ChatMessage], params: GenerationParams, tools: (any ToolHost)?)
        -> AsyncThrowingStream<ChatDelta, Error> {
        stream(model: model, messages: messages, params: params, tools: tools, resuming: nil)
    }

    func stream(model: ModelDescriptor, messages: [ChatMessage], params: GenerationParams, tools: (any ToolHost)?, resuming: AgentResume?)
        -> AsyncThrowingStream<ChatDelta, Error> {
        AgentLoop.stream(step: script, host: tools, maxToolRounds: 4, resume: resuming)
    }
}

private func storeURL() throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder.appending(path: "chats.store")
}

/// One app launch on the store at `url`: the launch sweep, then a chat screen's view model on `threadID`.
@MainActor
private func launch(
    _ engine: any ChatEngine, url: URL, thread threadID: UUID?, runs: RunCount, approver: ToolApprovalCenter,
    save: @escaping (ModelContext) throws -> Void = { try $0.save() }
) async throws -> (vm: ChatViewModel, context: ModelContext) {
    let registry = EngineRegistry()
    registry.register(engine)
    let models = ModelStore(registry: registry, defaults: testDefaults())
    await models.refresh()
    let context = ModelContext(try ModelContainer.anyRouter(storeURL: url))
    AgentRunSweep.run(context)
    let thread = try threadID.flatMap { id in
        try context.fetch(FetchDescriptor<ThreadRecord>(predicate: #Predicate { $0.id == id })).first
    }
    let vm = ChatViewModel(
        thread: thread, context: context, registry: registry, settings: AppSettings(defaults: testDefaults()), models: models,
        toolHost: { toolContext in
            AgentToolHost(builtIns: [SendNote(runs: runs)], search: nil, mcp: nil, approver: toolContext.approver)
        },
        approver: approver, save: save)
    return (vm, context)
}

/// A chat saved by a launch that was killed with `send_note` unfinished in its reply.
@MainActor
private func seed(_ url: URL, step: ToolStep, status: AgentRunStatus, rounds: [AgentSavedRound]) throws -> UUID {
    let context = ModelContext(try ModelContainer.anyRouter(storeURL: url))
    let thread = ThreadRecord(modelID: testModelWithTools().id)
    context.insert(thread)
    let question = MessageRecord(role: .user, content: "Send the note", createdAt: Date(timeIntervalSinceNow: -10))
    let reply = MessageRecord(role: .assistant, content: "Sending. ")
    for message in [question, reply] {
        context.insert(message)
        message.thread = thread
    }
    reply.toolSteps = [step]
    reply.failure = ReplyFailure(kind: .interrupted, detail: "The app closed while this reply was being written.")
    let run = AgentRunRecord(threadID: thread.id, messageID: reply.id, modelID: testModelWithTools().id)
    run.status = status
    run.node = status == .awaitingApproval ? .approve : .act
    run.state = AgentRunState(rounds: rounds, sideEffects: [step.call.id: .external])
    context.insert(run)
    try context.save()
    return thread.id
}

/// G4: a run that waits for approval survives the app being killed (agent design 1.3, evals E6 and E9).
@MainActor
struct AgentResumeChatTests {
    private let call = ToolCall(id: "c1", name: "send_note", argumentsJSON: "{}")
    private let sent = ToolResult(callID: "c1", name: "send_note", text: "sent", isError: false)

    private func storedRuns(_ context: ModelContext) throws -> [AgentRunRecord] {
        try context.fetch(FetchDescriptor<AgentRunRecord>())
    }

    /// E6: the next launch brings the card back on its step, and Allow runs the tool exactly once.
    @Test func aWaitingApprovalComesBackAfterARelaunchAndAllowRunsTheToolOnce() async throws {
        let url = try storeURL()
        let runs = RunCount()
        let alive = Flag()
        alive.value = true
        let first = RoundScript([[.text("Sending. "), .proposed(call), .end(finishReason: "tool_calls")]])
        let firstCenter = ToolApprovalCenter()
        let before = try await launch(
            LoopEngine(script: first), url: url, thread: nil, runs: runs, approver: firstCenter,
            save: { if alive.value { try $0.save() } })
        before.vm.input = "Send the note"
        _ = try #require(before.vm.send())
        #expect(await waitUntil { firstCenter.pending?.request.call.id == "c1" && before.vm.messages.last?.toolSteps.count == 1 })
        let waiting = try #require(try storedRuns(before.context).first)
        #expect(waiting.status == .awaitingApproval && waiting.node == .approve)
        #expect(waiting.state.rounds == [AgentSavedRound(text: "Sending. ", calls: [call])])
        #expect(waiting.state.sideEffects == ["c1": .external])
        let threadID = try #require(before.vm.thread?.id)
        let replyID = try #require(before.vm.messages.last?.id)
        // The app is killed: nothing more is saved, and the new process writes no reply yet.
        alive.value = false
        LiveReplies.shared.end(replyID)

        let second = RoundScript([[.text("It is sent."), .end(finishReason: "stop")]])
        let center = ToolApprovalCenter()
        let after = try await launch(LoopEngine(script: second), url: url, thread: threadID, runs: runs, approver: center)
        #expect(await waitUntil { center.pending?.request.call.id == "c1" }, "the card is back")
        let reply = try #require(after.vm.messages.last)
        #expect(reply.id == replyID && reply.toolSteps.map(\.id) == ["c1"], "on the step it waited on")
        #expect(after.vm.phase == .streaming && runs.value == 0)

        center.resolveCurrent(.allowOnce)
        #expect(await waitUntil { after.vm.phase == .idle })
        #expect(runs.value == 1, "Allow runs the tool exactly once")
        #expect(reply.toolSteps == [ToolStep(call: call, result: sent, sourceID: ToolSourceCatalog.device.id, approval: .allowOnce)])
        #expect(second.requests == [[AgentRound(text: "Sending. ", calls: [call], results: [sent])]], "round 2's request holds the result")
        #expect(reply.content == "Sending. It is sent." && reply.failure == nil)
        #expect(try storedRuns(after.context).isEmpty, "a run that ends is deleted")
    }

    /// E9: an approved write with no result when the app closed never runs again, and its row asks the user to check.
    @Test func anApprovedWriteWithNoResultIsNotRunAgainAfterARelaunch() async throws {
        let url = try storeURL()
        let threadID = try seed(
            url, step: ToolStep(call: call, result: nil, approval: .allowOnce), status: .running,
            rounds: [AgentSavedRound(text: "Sending. ", calls: [call])])
        let runs = RunCount()
        let center = ToolApprovalCenter()
        let after = try await launch(LoopEngine(script: RoundScript([])), url: url, thread: threadID, runs: runs, approver: center)
        let reply = try #require(after.vm.messages.last)
        #expect(runs.value == 0)
        #expect(center.pending == nil && after.vm.phase == .idle, "nothing goes on by itself")
        #expect(reply.toolSteps.first?.result?.text == ToolRowLogic.unfinishedText)
        #expect(ToolRowLogic.title(for: reply.toolSteps[0]) == "Used send_note may not have finished")
        #expect(try storedRuns(after.context).first?.status == .interrupted)
    }

    /// Apple's framework loop cannot be entered again: Allow runs the tool, then a new turn gets the earlier text and the
    /// result as text (agent design 1.3, Apple row).
    @Test func anAppleRunGoesOnAsANewTurnAfterARelaunch() async throws {
        let url = try storeURL()
        let threadID = try seed(url, step: ToolStep(call: call, result: nil), status: .awaitingApproval, rounds: [])
        let runs = RunCount()
        let center = ToolApprovalCenter()
        let engine = ScriptedEngine(models: [testModelWithTools()], chunks: ["It is sent."])
        let after = try await launch(engine, url: url, thread: threadID, runs: runs, approver: center)
        #expect(await waitUntil { center.pending?.request.call.id == "c1" }, "the card is back")
        center.resolveCurrent(.allowOnce)
        #expect(await waitUntil { after.vm.phase == .idle })
        #expect(runs.value == 1)
        let reply = try #require(after.vm.messages.last)
        #expect(reply.content == "Sending. It is sent.")
        #expect(reply.toolSteps.count == 1 && reply.toolSteps.first?.result == sent && reply.toolSteps.first?.approval == .allowOnce)
        #expect(engine.messagesSeen.lastTexts == [AgentLoop.continuationText([sent])])
    }

    /// A chat restored at launch opens before the device models are listed: the run goes on once they are, and only once.
    @Test func aWaitingRunGoesOnOnceItsModelIsListed() async throws {
        let url = try storeURL()
        let threadID = try seed(url, step: ToolStep(call: call, result: nil), status: .awaitingApproval, rounds: [])
        let runs = RunCount()
        let center = ToolApprovalCenter()
        let registry = EngineRegistry()
        registry.register(ScriptedEngine(models: [testModelWithTools()], chunks: ["It is sent."]))
        let models = ModelStore(registry: registry, defaults: testDefaults())
        let context = ModelContext(try ModelContainer.anyRouter(storeURL: url))
        let thread = try context.fetch(FetchDescriptor<ThreadRecord>(predicate: #Predicate { $0.id == threadID })).first
        let vm = ChatViewModel(
            thread: thread, context: context, registry: registry, settings: AppSettings(defaults: testDefaults()), models: models,
            toolHost: { toolContext in
                AgentToolHost(builtIns: [SendNote(runs: runs)], search: nil, mcp: nil, approver: toolContext.approver)
            },
            approver: center)
        #expect(vm.phase == .idle && center.pending == nil, "no model listed yet")
        await models.refresh()
        vm.resumeWaitingRun()
        #expect(await waitUntil { center.pending?.request.call.id == "c1" })
        vm.resumeWaitingRun()
        #expect(vm.messages.last?.toolSteps.count == 1, "a second call while it streams does nothing")
        center.resolveCurrent(.allowOnce)
        #expect(await waitUntil { vm.phase == .idle })
        #expect(runs.value == 1)
    }
}
