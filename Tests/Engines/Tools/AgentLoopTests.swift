import Foundation
import Testing
@testable import AnyRouter

/// A step function that plays one scripted round per call and keeps what it was asked.
private final class ScriptedStep: StepFunction, @unchecked Sendable {
    let budget: RunBudgetLogic.Budget?
    private let lock = NSLock()
    private var scripts: [[StepEvent]]
    private var asked: [(rounds: [AgentRound], toolsOn: Bool)] = []

    init(_ scripts: [[StepEvent]], budget: RunBudgetLogic.Budget? = nil) {
        self.scripts = scripts
        self.budget = budget
    }

    var requests: [(rounds: [AgentRound], toolsOn: Bool)] { lock.withLock { asked } }

    /// Only result text counts, one token a character, so the budget tests can do the sums.
    func tokens(_ rounds: [AgentRound], toolsOn: Bool) -> Int {
        rounds.flatMap(\.results).reduce(0) { $0 + $1.text.count }
    }

    func step(_ rounds: [AgentRound], toolsOn: Bool) -> AsyncThrowingStream<StepEvent, Error> {
        let events = lock.withLock { () -> [StepEvent] in
            asked.append((rounds, toolsOn))
            return scripts.count > 1 ? scripts.removeFirst() : scripts.first ?? []
        }
        return AsyncThrowingStream { continuation in
            for event in events { continuation.yield(event) }
            continuation.finish()
        }
    }
}

private struct Failing: Error, Equatable {}

/// A step function whose request fails.
private struct BrokenStep: StepFunction {
    let budget: RunBudgetLogic.Budget? = nil
    func tokens(_ rounds: [AgentRound], toolsOn: Bool) -> Int { 0 }
    func step(_ rounds: [AgentRound], toolsOn: Bool) -> AsyncThrowingStream<StepEvent, Error> {
        AsyncThrowingStream { $0.finish(throwing: Failing()) }
    }
}

/// Answers `boom` with an error, `slow` after a long wait, `page` with `pageLength` characters, anything else with its arguments.
private final class LoopHost: ToolHost, @unchecked Sendable {
    let specs = [ToolSpec(name: "look", title: nil, description: "", schema: "{}", isReadOnly: true)]
    var pageLength = 6_000
    let started = Flag()
    private let lock = NSLock()
    private var ran: [ToolCall] = []

    var calls: [ToolCall] { lock.withLock { ran } }

    func execute(_ call: ToolCall) async -> ToolResult {
        lock.withLock { ran.append(call) }
        switch call.name {
        case "boom": return ToolResult(callID: call.id, name: call.name, text: "boom failed", isError: true)
        case "slow":
            started.value = true
            try? await Task.sleep(for: .seconds(30))
            return ToolResult(callID: call.id, name: call.name, text: "The tool call was cancelled.", isError: true)
        case "page": return ToolResult(callID: call.id, name: call.name, text: String(repeating: "x", count: pageLength), isError: false)
        default: return ToolResult(callID: call.id, name: call.name, text: "saw \(call.argumentsJSON)", isError: false)
        }
    }
}

private func call(_ id: String, _ name: String = "look", _ arguments: String = "{}") -> ToolCall {
    ToolCall(id: id, name: name, argumentsJSON: arguments)
}

private func collect(_ stream: AsyncThrowingStream<ChatDelta, Error>) async -> (deltas: [ChatDelta], error: Error?) {
    var deltas: [ChatDelta] = []
    do {
        for try await delta in stream { deltas.append(delta) }
        return (deltas, nil)
    } catch {
        return (deltas, error)
    }
}

struct AgentLoopTests {
    @Test func aRoundStreamsAsItComesAndTheTailSumsEveryRound() async {
        let first = ResponseMetadata(provider: "one", promptTokens: 10)
        let second = ResponseMetadata(provider: "two", promptTokens: 5)
        let step = ScriptedStep([
            [.reasoning("hmm"), .text("Let me look. "), .proposed(call("c1")), .usage(prompt: 10, completion: 2), .metadata(first),
             .end(finishReason: "tool_calls")],
            [.text("Done."), .usage(prompt: 5, completion: 1), .metadata(second), .end(finishReason: "stop")],
        ])
        let host = LoopHost()
        let run = await collect(AgentLoop.stream(step: step, host: host, maxToolRounds: 4))
        #expect(run.error == nil)
        let result = ToolResult(callID: "c1", name: "look", text: "saw {}", isError: false)
        #expect(run.deltas == [
            .reasoning("hmm"), .text("Let me look. "), .toolCall(call("c1")), .toolResult(result), .text("Done."),
            .metadata(ResponseMetadata.combining(first, second)!), .usage(prompt: 15, completion: 3), .done(finishReason: "stop"),
        ])
        #expect(step.requests.map(\.toolsOn) == [true, true])
        #expect(step.requests[1].rounds == [AgentRound(text: "Let me look. ", calls: [call("c1")], results: [result])])
    }

    @Test func theRoundAfterTheLastToolRoundHasToolsOffAndItsCallsDoNotRun() async {
        let step = ScriptedStep([[.proposed(call("c")), .end(finishReason: "tool_calls")]])
        let host = LoopHost()
        let run = await collect(AgentLoop.stream(step: step, host: host, maxToolRounds: 2))
        #expect(step.requests.map(\.toolsOn) == [true, true, false])
        #expect(host.calls.count == 2)
        #expect(run.deltas.last == .done(finishReason: "tool_calls"))
    }

    @Test func withoutAHostNothingRunsAndToolsAreOff() async {
        let step = ScriptedStep([[.text("hi"), .proposed(call("c")), .end(finishReason: nil)]])
        let run = await collect(AgentLoop.stream(step: step, host: nil, maxToolRounds: 8))
        #expect(run.deltas == [.text("hi"), .done(finishReason: nil)])
        #expect(step.requests.map(\.toolsOn) == [false])
    }

    @Test func theTextAModelWroteGoesBackInsteadOfTheTextShown() async {
        let step = ScriptedStep([
            [.text("Looking."), .wrote("Looking.<call>"), .proposed(call("c")), .end(finishReason: "stop")],
            [.text("Done."), .end(finishReason: "stop")],
        ])
        _ = await collect(AgentLoop.stream(step: step, host: LoopHost(), maxToolRounds: 4))
        #expect(step.requests[1].rounds.first?.text == "Looking.<call>")
    }

    /// Agent design E5: the error reaches the model; the same failing call is not run again, and the model answers
    /// without tools. A failing call with other arguments still runs.
    @Test func aRepeatedFailingCallIsNotRunAgainAndTheNextRoundAnswers() async {
        let step = ScriptedStep([
            [.proposed(call("a", "boom", #"{"x":1}"#)), .end(finishReason: "tool_calls")],
            [.proposed(call("b", "boom", #"{"x":2}"#)), .end(finishReason: "tool_calls")],
            [.proposed(call("c", "boom", #"{"x":1}"#)), .end(finishReason: "tool_calls")],
            [.text("It failed."), .end(finishReason: "stop")],
        ])
        let host = LoopHost()
        let run = await collect(AgentLoop.stream(step: step, host: host, maxToolRounds: 8))
        #expect(host.calls.map(\.id) == ["a", "b"])
        #expect(step.requests.map(\.toolsOn) == [true, true, true, false])
        let last = step.requests[3].rounds
        #expect(last[0].results.first?.text == "boom failed", "the error text is in the next request")
        #expect(last[2].results == [ToolResult(callID: "c", name: "boom", text: AgentLoop.repeatedFailureText, isError: true)])
        #expect(run.deltas.filter { if case .toolCall = $0 { true } else { false } }.count == 2, "the repeat is not shown as run")
        #expect(run.deltas.last == .done(finishReason: "stop"))
    }

    @Test func aFailedRequestEndsTheStreamWithItsError() async {
        let run = await collect(AgentLoop.stream(step: BrokenStep(), host: LoopHost(), maxToolRounds: 4))
        #expect(run.error as? Failing == Failing())
        #expect(run.deltas.isEmpty)
    }

    @Test func stoppingDuringACallEndsTheRunWithoutAnotherRound() async throws {
        let step = ScriptedStep([[.proposed(call("s", "slow")), .end(finishReason: "tool_calls")]])
        let host = LoopHost()
        let consumer = Task { _ = await collect(AgentLoop.stream(step: step, host: host, maxToolRounds: 4)) }
        for _ in 0..<500 where !host.started.value { try await Task.sleep(for: .milliseconds(10)) }
        #expect(host.started.value)
        consumer.cancel()
        _ = await consumer.value
        #expect(step.requests.count == 1)
    }

    /// A device run cuts each new result to what is left and clears the oldest when the next round would not fit.
    @Test func aDeviceRunCutsNewResultsAndClearsOldOnes() async {
        let step = ScriptedStep([[.proposed(call("p", "page")), .end(finishReason: "tool_calls")]],
                                budget: RunBudgetLogic.Budget(window: 4096, onDevice: true))
        let host = LoopHost()
        _ = await collect(AgentLoop.stream(step: step, host: host, maxToolRounds: 5))
        let budget = RunBudgetLogic.Budget(window: 4096, onDevice: true)
        for request in step.requests {
            #expect(step.tokens(request.rounds, toolsOn: request.toolsOn) <= budget.limit)
        }
        let last = step.requests.last?.rounds.flatMap(\.results).map(\.text) ?? []
        #expect(last.count == 5)
        #expect(last.suffix(3).allSatisfy { $0.hasSuffix("[Cut to fit the model's window.]") })
        #expect(last.first?.hasPrefix("[Result cleared: page") == true)
    }

    /// A cloud run sends results whole and clears only when it frees at least 8,000 tokens (agent design 3.4).
    @Test func aCloudRunClearsOnlyInLargeSteps() async {
        let budget = RunBudgetLogic.Budget(window: 20_000, onDevice: false)
        let step = ScriptedStep([[.proposed(call("p", "page")), .end(finishReason: "tool_calls")]], budget: budget)
        _ = await collect(AgentLoop.stream(step: step, host: LoopHost(), maxToolRounds: 5))
        let cleared = step.requests.map { $0.rounds.flatMap(\.results).filter { $0.text.hasPrefix("[Result cleared") }.count }
        #expect(cleared == [0, 0, 0, 0, 0, 2], "four pages over the limit cannot free 8,000 tokens; five can")
        #expect(step.requests[4].rounds.flatMap(\.results).allSatisfy { $0.text.count == 6_000 }, "results are not cut")
    }
}

/// A host that keeps the rounds the loop announces before running them, and the calls it ran.
private final class RoundHost: ToolHost, @unchecked Sendable {
    let specs = [ToolSpec(name: "look", title: nil, description: "", schema: "{}", isReadOnly: true)]
    private let lock = NSLock()
    private var announced: [AgentSavedRound] = []
    private var ran: [String] = []

    var rounds: [AgentSavedRound] { lock.withLock { announced } }
    var calls: [String] { lock.withLock { ran } }

    func willRun(_ text: String, calls: [ToolCall]) async {
        lock.withLock { announced.append(AgentSavedRound(text: text, calls: calls)) }
    }

    func execute(_ call: ToolCall) async -> ToolResult {
        lock.withLock { ran.append(call.id) }
        return ToolResult(callID: call.id, name: call.name, text: "saw \(call.id)", isError: false)
    }
}

/// G4: a run that stopped for approval goes on from where it stopped (agent design 1.3).
struct AgentLoopResumeTests {
    @Test func everyRoundIsAnnouncedWithAllItsCallsBeforeTheFirstRuns() async {
        let step = ScriptedStep([
            [.text("Shown. "), .wrote("Shown. <call/>"), .proposed(call("c1")), .proposed(call("c2")), .end(finishReason: "tool_calls")],
            [.text("Done."), .end(finishReason: "stop")],
        ])
        let host = RoundHost()
        _ = await collect(AgentLoop.stream(step: step, host: host, maxToolRounds: 4))
        #expect(host.rounds == [AgentSavedRound(text: "Shown. <call/>", calls: [call("c1"), call("c2")])], "the text the next request carries")
        #expect(host.calls == ["c1", "c2"])
    }

    @Test func aResumedRunGoesOnFromTheFirstCallWithoutAResult() async {
        let one = ToolResult(callID: "c1", name: "look", text: "one", isError: false)
        let two = ToolResult(callID: "c2", name: "look", text: "two", isError: false)
        let first = AgentRound(text: "Look first.", calls: [call("c1")], results: [one])
        let pending = AgentRound(text: "Now two more.", calls: [call("c2"), call("c3")], results: [two])
        let step = ScriptedStep([[.text("All done."), .end(finishReason: "stop")]])
        let host = RoundHost()
        let run = await collect(AgentLoop.stream(
            step: step, host: host, maxToolRounds: 4, resume: AgentResume(rounds: [first], pending: pending)))
        #expect(host.calls == ["c3"], "c2 ran before the app closed")
        #expect(host.rounds.isEmpty, "the stopped round was saved before the app closed")
        let three = ToolResult(callID: "c3", name: "look", text: "saw c3", isError: false)
        #expect(run.deltas == [.toolCall(call("c3")), .toolResult(three), .text("All done."), .done(finishReason: "stop")])
        #expect(step.requests.count == 1, "no model round before the waiting call runs")
        #expect(step.requests.first?.rounds == [first, AgentRound(text: pending.text, calls: pending.calls, results: [two, three])])
    }

    @Test func anAppleRunGoesOnAsANewTurnWithTheResultsAsText() async {
        let engine = ScriptedEngine(chunks: ["Sent."])
        let earlier = ToolResult(callID: "c0", name: "look", text: "zero", isError: false)
        let run = await collect(AgentLoop.continuing(
            engine: engine, model: testModel(), messages: [ChatMessage(role: .user, content: "send it")], params: GenerationParams(),
            host: RoundHost(), text: "Sending.", done: [earlier], calls: [call("c1")]))
        let result = ToolResult(callID: "c1", name: "look", text: "saw c1", isError: false)
        #expect(run.deltas == [.toolCall(call("c1")), .toolResult(result), .text("Sent."), .done(finishReason: "stop")])
        #expect(engine.messagesSeen.lastTexts == ["Your tool calls answered:\nlook: zero\nlook: saw c1\nGo on with your answer."])
    }
}
