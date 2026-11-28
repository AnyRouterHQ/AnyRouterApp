import Foundation
import Testing
@testable import AnyRouter

/// Plays one scripted round per request (the last one again when it runs out) and keeps whether tools were on.
private final class ChildScript: StepFunction, @unchecked Sendable {
    let budget: RunBudgetLogic.Budget? = nil
    private let lock = NSLock()
    private var scripts: [[StepEvent]]
    private var asked: [Bool] = []

    init(_ scripts: [[StepEvent]]) { self.scripts = scripts }

    var toolsOn: [Bool] { lock.withLock { asked } }

    func tokens(_ rounds: [AgentRound], toolsOn: Bool) -> Int { 0 }

    func step(_ rounds: [AgentRound], toolsOn: Bool) -> AsyncThrowingStream<StepEvent, Error> {
        let events = lock.withLock { () -> [StepEvent] in
            asked.append(toolsOn)
            return scripts.count > 1 ? scripts.removeFirst() : scripts.first ?? []
        }
        return AsyncThrowingStream { continuation in
            for event in events { continuation.yield(event) }
            continuation.finish()
        }
    }
}

/// A request that never answers until it is stopped.
private final class HangingStep: StepFunction, @unchecked Sendable {
    let budget: RunBudgetLogic.Budget? = nil
    let started = Flag()
    let stopped = Flag()

    func tokens(_ rounds: [AgentRound], toolsOn: Bool) -> Int { 0 }

    func step(_ rounds: [AgentRound], toolsOn: Bool) -> AsyncThrowingStream<StepEvent, Error> {
        AsyncThrowingStream { continuation in
            self.started.value = true
            continuation.onTermination = { _ in self.stopped.value = true }
        }
    }
}

private struct BusyServer: LocalizedError {
    var errorDescription: String? { "The server is busy." }
}

/// A request that fails.
private struct FailingStep: StepFunction {
    let budget: RunBudgetLogic.Budget? = nil
    func tokens(_ rounds: [AgentRound], toolsOn: Bool) -> Int { 0 }
    func step(_ rounds: [AgentRound], toolsOn: Bool) -> AsyncThrowingStream<StepEvent, Error> {
        AsyncThrowingStream { $0.finish(throwing: BusyServer()) }
    }
}

/// The chat's tools: the four a subagent may use, and a write, a sensitive read and an external tool it may not.
private final class ChatTools: ToolHost, @unchecked Sendable {
    let specs: [ToolSpec] = {
        func spec(_ name: String, _ sideEffect: ToolSideEffect) -> ToolSpec {
            ToolSpec(name: name, title: nil, description: "", schema: "{}", sideEffect: sideEffect)
        }
        return [
            spec(WebSearchBinding.name, .read), spec(FetchURLTool.toolName, .read), spec("current_date_time", .read), spec("calculator", .read),
            spec(NotesLogic.name, .write), spec("search_chats", .sensitiveRead), spec(DecideTool.toolName, .external),
        ]
    }()
    private let lock = NSLock()
    private var ran: [String] = []
    private var announced: [String] = []

    var calls: [String] { lock.withLock { ran } }
    var rounds: [String] { lock.withLock { announced } }

    func execute(_ call: ToolCall) async -> ToolResult {
        lock.withLock { ran.append(call.name) }
        return ToolResult(callID: call.id, name: call.name, text: "\(call.name) answered", isError: false)
    }

    func sourceID(forTool name: String) -> String? { "source-\(name)" }

    func willRun(_ text: String, calls: [ToolCall]) async { lock.withLock { announced.append(text) } }

    func recitation() async -> String? { "Your notes" }
}

/// What the runner asked the model with.
private final class ChildRequests: @unchecked Sendable {
    private let lock = NSLock()
    private var all: [(messages: [String], specs: [ToolSpec])] = []
    var requests: [(messages: [String], specs: [ToolSpec])] { lock.withLock { all } }
    func add(_ messages: [ChatMessage], _ specs: [ToolSpec]) { lock.withLock { all.append((messages.map(\.content), specs)) } }
}

/// The steps the chat would show: each update nests the subagent's calls under the call that started it.
@MainActor
private final class ShownSteps {
    var steps: [ToolStep] = []
    var updates = 0
}

private func search(_ id: String) -> StepEvent {
    .proposed(ToolCall(id: id, name: WebSearchBinding.name, argumentsJSON: #"{"query":"\#(id)"}"#))
}

private func delegate(_ id: String = "d1", _ arguments: String = #"{"task":"How do Swift actors work?","title":"Actors","hints":"Swift docs"}"#) -> ToolCall {
    ToolCall(id: id, name: SubagentLogic.toolName, argumentsJSON: arguments)
}

@MainActor
private func runner(_ step: any StepFunction, tools: ChatTools = ChatTools(), asked: ChildRequests = ChildRequests(), shown: ShownSteps = ShownSteps()) -> SubagentRunner {
    SubagentRunner(
        makeStep: { messages, specs in
            asked.add(messages, specs)
            return step
        },
        tools: SubagentToolHost(base: tools),
        onSteps: { call, children in
            shown.steps = SubagentLogic.nesting(children, under: call, in: shown.steps)
            shown.updates += 1
        })
}

private func collect(_ stream: AsyncThrowingStream<ChatDelta, Error>) async -> [ChatDelta] {
    var deltas: [ChatDelta] = []
    do {
        for try await delta in stream { deltas.append(delta) }
    } catch {}
    return deltas
}

/// S1: a cloud model hands a bounded research task to a subagent with its own small context and tool budget, and gets
/// back one summary (PLAN D28, D25 unit 5).
@MainActor
struct SubagentRunTests {
    /// Two searches, then a summary: the parent's call shows both searches as its steps and gets the summary back, with
    /// what the subagent spent.
    @Test func aSubagentSearchesTwiceAndTheParentGetsItsSummaryAndSpend() async throws {
        let child = ChildScript([
            [.text("Let me search. "), search("s1"), .usage(Usage(input: 100, output: 10)), .end(finishReason: "tool_calls")],
            [search("s2"), .usage(Usage(input: 200, output: 20)), .end(finishReason: "tool_calls")],
            [.text("Actors run one call at a time.\nSources: https://docs.example.com/actors"), .usage(Usage(input: 300, output: 30)),
             .metadata(ResponseMetadata(costUSD: Decimal(string: "0.002"))), .end(finishReason: "stop")],
        ])
        let tools = ChatTools()
        let asked = ChildRequests()
        let shown = ShownSteps()
        let parent = ChildScript([[.proposed(delegate()), .end(finishReason: "tool_calls")], [.text("Here it is."), .end(finishReason: "stop")]])
        let host = SubagentHost(base: tools, runner: runner(child, tools: tools, asked: asked, shown: shown))
        let deltas = await collect(AgentLoop.stream(step: parent, host: host, maxToolRounds: 8))

        let results = deltas.compactMap { delta -> ToolResult? in
            if case .toolResult(let result) = delta { return result }
            return nil
        }
        let result = try #require(results.first)
        #expect(results.count == 1, "the subagent's own calls stay out of the parent's stream")
        #expect(result.text == "Actors run one call at a time.\nSources: https://docs.example.com/actors", "only the last round's text")
        #expect(!result.isError)
        #expect(result.costUSD == Decimal(string: "0.002"))
        #expect(result.promptTokens == 600 && result.completionTokens == 60)
        #expect(child.toolsOn == [true, true, true])
        #expect(tools.calls == [WebSearchBinding.name, WebSearchBinding.name])
        #expect(asked.requests.map(\.messages) == [["How do Swift actors work?\n\nHints: Swift docs"]], "the task only, not the chat")
        #expect(tools.rounds == [""], "only the parent's round is announced; the subagent's are not saved with the run")

        let shownStep = try #require(shown.steps.first)
        #expect(shown.steps.count == 1 && shown.updates == 4)
        let subagent = try #require(SubagentLogic.make(shownStep))
        #expect(subagent.steps.map(\.id) == ["s1", "s2"])
        #expect(subagent.steps.allSatisfy { $0.result?.text == "web_search answered" && $0.sourceID == "source-web_search" })
        #expect(SubagentLogic.heading(subagent) == "Subagent · Actors · 2 steps")
    }

    /// The subagent never gets a write, a sensitive read, an external tool or another subagent, and a call to one is refused.
    @Test func theSubagentGetsOnlyTheFourReadToolsAndCannotCallAnother() async {
        let child = ChildScript([
            [.proposed(ToolCall(id: "n", name: NotesLogic.name, argumentsJSON: "{}")), .end(finishReason: "tool_calls")],
            [.text("Done."), .end(finishReason: "stop")],
        ])
        let tools = ChatTools()
        let asked = ChildRequests()
        let shown = ShownSteps()
        let result = await runner(child, tools: tools, asked: asked, shown: shown).run(delegate())
        let names = asked.requests.first?.specs.map(\.name)
        #expect(names == [WebSearchBinding.name, FetchURLTool.toolName, "current_date_time", "calculator"])
        #expect(asked.requests.first?.specs.allSatisfy { $0.sideEffect == .read } == true)
        #expect(tools.calls.isEmpty, "the write never runs")
        #expect(shown.steps.first?.children?.first?.result?.text == "Unknown tool: notes.")
        #expect(result.text == "Done.")
    }

    /// At most four requests: three may call tools, the fourth must answer, and its calls do not run.
    @Test func theRoundLimitStopsTheSubagent() async {
        let child = ChildScript([
            [search("s1"), .end(finishReason: "tool_calls")],
            [search("s2"), .end(finishReason: "tool_calls")],
            [search("s3"), .end(finishReason: "tool_calls")],
            [.text("Best guess."), search("s4"), .end(finishReason: "tool_calls")],
        ])
        let tools = ChatTools()
        let result = await runner(child, tools: tools).run(delegate())
        #expect(child.toolsOn == [true, true, true, false])
        #expect(tools.calls.count == 3)
        #expect(result.text == "Best guess.")
    }

    /// The round that reaches the token budget is the last with tools: its calls run, then the next request answers.
    @Test func theTokenBudgetStopsTheSubagent() async {
        let child = ChildScript([
            [search("s1"), .usage(Usage(input: 20_000, output: 500)), .end(finishReason: "tool_calls")],
            [search("s2"), .usage(Usage(input: 9_000, output: 500)), .end(finishReason: "tool_calls")],
            [.text("Short answer."), .usage(Usage(input: 1_000, output: 50)), .end(finishReason: "stop")],
        ])
        let tools = ChatTools()
        let result = await runner(child, tools: tools).run(delegate())
        #expect(child.toolsOn == [true, true, false])
        #expect(tools.calls.count == 2)
        #expect(result.text == "Short answer.")
        #expect(result.promptTokens == 30_000 && result.completionTokens == 1_050)
    }

    @Test func noTaskNoSummaryOrAFailedRequestComeBackAsErrors() async {
        let asked = ChildRequests()
        let missing = await runner(ChildScript([]), asked: asked).run(delegate("d", #"{"task":"  "}"#))
        #expect(missing.isError && missing.text == SubagentLogic.missingTaskText)
        #expect(asked.requests.isEmpty, "no request without a task")

        let silent = await runner(ChildScript([[.end(finishReason: "stop")]])).run(delegate())
        #expect(silent.isError && silent.text == SubagentLogic.noSummaryText)
        #expect(silent.costUSD == nil && silent.promptTokens == nil)

        let failed = await runner(FailingStep()).run(delegate())
        #expect(failed.isError && failed.text == "The server is busy.")
    }

    /// Stop on the parent cancels the subagent's request too.
    @Test func stoppingTheParentStopsTheSubagent() async throws {
        let child = HangingStep()
        let parent = ChildScript([[.proposed(delegate()), .end(finishReason: "tool_calls")]])
        let host = SubagentHost(base: ChatTools(), runner: runner(child))
        let consumer = Task { await collect(AgentLoop.stream(step: parent, host: host, maxToolRounds: 8)) }
        for _ in 0..<500 where !child.started.value { try await Task.sleep(for: .milliseconds(10)) }
        #expect(child.started.value)
        consumer.cancel()
        _ = await consumer.value
        for _ in 0..<500 where !child.stopped.value { try await Task.sleep(for: .milliseconds(10)) }
        #expect(child.stopped.value)
        #expect(parent.toolsOn.count == 1, "the parent asks no more")
    }

    /// The parent keeps its other tools; its round announcements and notes still reach the chat's host.
    @Test func theParentKeepsItsToolsAndAddsTheDelegationOnce() async {
        let tools = ChatTools()
        let host = SubagentHost(base: tools, runner: runner(ChildScript([])))
        #expect(host.specs.map(\.name) == tools.specs.map(\.name) + [SubagentLogic.toolName])
        #expect(host.specs.last == SubagentLogic.spec)
        #expect(host.sourceID(forTool: SubagentLogic.toolName) == ToolSourceCatalog.anyRouter.id)
        #expect(host.sourceID(forTool: "calculator") == "source-calculator")
        let answer = await host.execute(ToolCall(id: "c", name: "calculator", argumentsJSON: "{}"))
        #expect(answer.text == "calculator answered")
        await host.willRun("thinking", calls: [])
        #expect(tools.rounds == ["thinking"])
        #expect(await host.recitation() == "Your notes")
    }
}

struct SubagentLogicRunTests {
    private func step(_ id: String, _ name: String, args: String = "{}", result: ToolResult? = nil, children: [ToolStep]? = nil) -> ToolStep {
        ToolStep(call: ToolCall(id: id, name: name, argumentsJSON: args), result: result, children: children)
    }

    private func done(_ id: String, _ name: String, error: Bool = false) -> ToolResult {
        ToolResult(callID: id, name: name, text: "ok", isError: error)
    }

    @Test func theToolTakesATaskAndOptionalHints() throws {
        #expect(SubagentLogic.message(from: #"{"task":" Find it "}"#) == "Find it")
        #expect(SubagentLogic.message(from: #"{"task":"Find it","hints":" docs "}"#) == "Find it\n\nHints: docs")
        #expect(SubagentLogic.message(from: #"{"task":"Find it","hints":"  "}"#) == "Find it")
        for broken in ["", "not json", #"{"task":"   "}"#, #"{"hints":"docs"}"#] {
            #expect(SubagentLogic.message(from: broken) == nil, "\(broken)")
        }
        let schema = try #require(JSONValue.parse(SubagentLogic.spec.schema.json))
        #expect(schema["required"]?.array == [.string("task")])
        #expect(SubagentLogic.spec.name == SubagentLogic.toolName && SubagentLogic.spec.sideEffect == .read)
        #expect(SubagentLogic.instructions.contains("Sources:") && !SubagentLogic.instructions.isEmpty)
        #expect(SubagentLogic.canResearch([SubagentLogic.spec, ToolSpec(name: FetchURLTool.toolName, title: nil, description: "", schema: "{}", isReadOnly: true)]))
        #expect(!SubagentLogic.canResearch([ToolSpec(name: "calculator", title: nil, description: "", schema: "{}", isReadOnly: true)]))
        #expect(SubagentLogic.childToolNames == [WebSearchBinding.name, FetchURLTool.toolName, "current_date_time", "calculator"])
    }

    @Test func theAnswerListsThePagesReadThatTheSummaryDoesNotName() {
        let read = step("f1", FetchURLTool.toolName, args: #"{"url":"https://a.example.com/one"}"#, result: done("f1", FetchURLTool.toolName))
        let again = step("f2", FetchURLTool.toolName, args: #"{"url":"https://a.example.com/one"}"#, result: done("f2", FetchURLTool.toolName))
        let named = step("f3", FetchURLTool.toolName, args: #"{"url":"https://b.example.com/two"}"#, result: done("f3", FetchURLTool.toolName))
        let failed = step("f4", FetchURLTool.toolName, args: #"{"url":"https://c.example.com"}"#, result: done("f4", FetchURLTool.toolName, error: true))
        let running = step("f5", FetchURLTool.toolName, args: #"{"url":"https://d.example.com"}"#)
        let searched = step("s", WebSearchBinding.name, args: #"{"query":"https://e.example.com"}"#, result: done("s", WebSearchBinding.name))
        let steps = [read, again, named, failed, running, searched]
        #expect(SubagentLogic.pagesRead(steps) == ["https://a.example.com/one", "https://b.example.com/two"])
        #expect(SubagentLogic.answer(" See https://b.example.com/two \n", steps: steps)
            == "See https://b.example.com/two\n\nPages read:\n- https://a.example.com/one")
        #expect(SubagentLogic.answer("Plain.", steps: [searched]) == "Plain.")
        #expect(SubagentLogic.answer(" \n ", steps: steps) == nil)
    }

    @Test func childStepsNestUnderTheirCallEvenBeforeItsRowArrives() {
        let call = ToolCall(id: "d", name: SubagentLogic.toolName, argumentsJSON: "{}")
        let children = [step("s1", WebSearchBinding.name)]
        let early = SubagentLogic.nesting(children, under: call, in: [step("a", "calculator")])
        #expect(early.map(\.id) == ["a", "d"])
        #expect(early.last?.children == children && early.last?.result == nil)
        let later = SubagentLogic.nesting(children + [step("s2", FetchURLTool.toolName)], under: call, in: early)
        #expect(later.map(\.id) == ["a", "d"])
        #expect(later.last?.children?.map(\.id) == ["s1", "s2"])
        #expect(later.first?.children == nil)
    }

    @Test func aSubagentStepStillRunningAtTheEndIsCancelled() {
        let finished = step("s1", WebSearchBinding.name, result: done("s1", WebSearchBinding.name))
        let running = step("s2", WebSearchBinding.name)
        let settled = SubagentLogic.settled([step("a", "calculator"), step("d", SubagentLogic.toolName, children: [finished, running])])
        #expect(settled.first?.children == nil)
        #expect(settled.last?.children?.first == finished)
        let cut = settled.last?.children?.last?.result
        #expect(cut?.text == ToolRowLogic.cancelledText && cut?.isError == true && cut?.callID == "s2")
    }

    @Test func aSubagentsTokensAreKeptApartFromTheReplysOwn() {
        var spent = done("d", SubagentLogic.toolName)
        spent.promptTokens = 600
        spent.completionTokens = 60
        let steps = [step("d", SubagentLogic.toolName, result: spent), step("c", "calculator", result: done("c", "calculator")), step("r", "calculator")]
        let tokens = SubagentLogic.spentTokens(steps)
        #expect(tokens.prompt == 600 && tokens.completion == 60)

        let reply = ResponseMetadata(costUSD: 1, promptTokens: 100, completionTokens: 10)
        #expect(SubagentLogic.adding((0, 0), to: reply) == reply)
        let added = SubagentLogic.adding(tokens, to: reply)
        #expect(added.promptTokens == 100 && added.completionTokens == 10 && added.costUSD == 1, "the reply's own counts stay")
        #expect(added.subagentPromptTokens == 600 && added.subagentCompletionTokens == 60)
    }
}
