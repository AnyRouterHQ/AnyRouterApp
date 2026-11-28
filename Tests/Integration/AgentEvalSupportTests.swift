import XCTest

@testable import AnyRouter

/// The parts of the live agent eval that need no model, so main CI keeps them honest: the fixture, the tool host the cases
/// run on, the scoring, the report file, and the whole harness driven by a scripted engine.
final class AgentEvalSupportTests: XCTestCase {
    private func caseNamed(_ id: String) throws -> AgentToolCase {
        let all = try AgentEvalFixtures.toolCases()
        return try XCTUnwrap(all.first { $0.id == id }, id)
    }

    private let qwen = ModelDescriptor(
        id: "gguf/org/Qwen-test-GGUF/qwen-test-Q4_0.gguf", source: .gguf, displayName: "Qwen test", contextLength: 32768,
        capabilities: [], sizeBytes: nil, isInstalled: true)

    // MARK: Fixture

    func testFixtureHasTwentyCasesInTwoLanguagesAndEveryToolAndNone() throws {
        let cases = try AgentEvalFixtures.toolCases()
        XCTAssertEqual(cases.count, 20)
        XCTAssertEqual(Set(cases.map(\.id)).count, cases.count, "ids are unique")
        XCTAssertGreaterThanOrEqual(cases.filter { $0.language == "en" }.count, 8)
        XCTAssertGreaterThanOrEqual(cases.filter { $0.language == "vi" }.count, 8)
        for tool in ["current_date_time", "calculator", "web_search", "fetch_url"] {
            XCTAssertGreaterThanOrEqual(cases.filter { $0.expectTool == tool }.count, 3, tool)
        }
        XCTAssertGreaterThanOrEqual(cases.filter { $0.expectTool == nil }.count, 3, "keeps prompts that need no tool")
        for item in cases {
            XCTAssertFalse(item.prompt.isEmpty, item.id)
            XCTAssertFalse(item.mustContain.isEmpty, "\(item.id) checks the answer")
            if item.expectTool == "web_search" || item.expectTool == "fetch_url" {
                XCTAssertNotNil(item.fixtureResult, "\(item.id) needs a stub result")
            }
            if item.expectTool == "fetch_url" {
                XCTAssertFalse(item.argsContain.isEmpty, "\(item.id) must check the URL")
                XCTAssertTrue(item.argsContain.allSatisfy { item.prompt.contains($0) }, "\(item.id): the URL is in the prompt")
            }
        }
    }

    func testEveryFixtureAnswerNeedleIsInItsStubResultOrComesFromARealTool() throws {
        for item in try AgentEvalFixtures.toolCases() where item.fixtureResult != nil {
            let result = try XCTUnwrap(item.fixtureResult)
            XCTAssertTrue(
                item.mustContain.allSatisfy { AgentEvalScoring.contains(result, $0) }, "\(item.id): a model that reads the result can pass")
        }
    }

    // MARK: Host

    func testHostOffersTheFourToolsAndRunsThemWithTheGuard() async throws {
        let search = try caseNamed("fetch-changelog-en")
        let approver = EvalApprover()
        let host = AgentEvalHost.make(for: search, source: .gguf, approver: approver)
        XCTAssertEqual(host.specs.map(\.name), ["current_date_time", "calculator", "web_search", "fetch_url"])

        let sum = await host.execute(ToolCall(id: "1", name: "calculator", argumentsJSON: #"{"expression":"17*23"}"#))
        XCTAssertEqual(sum.text, "391")
        XCTAssertFalse(sum.isError)

        let page = await host.execute(ToolCall(id: "2", name: "fetch_url", argumentsJSON: #"{"url":"https://zorblax.example/changelog"}"#))
        XCTAssertEqual(page.text, search.fixtureResult)
        XCTAssertEqual(approver.asked, 0, "a URL the user wrote runs without asking")

        let other = await host.execute(ToolCall(id: "3", name: "fetch_url", argumentsJSON: #"{"url":"https://elsewhere.example/page"}"#))
        XCTAssertFalse(other.isError)
        XCTAssertEqual(approver.asked, 1, "a URL the user never wrote asks first")
    }

    // MARK: Scoring

    func testAnswerTextIsWhatFollowsTheThinking() {
        XCTAssertEqual(AgentEvalScoring.answerText(from: "<think>2+2</think>\n\n4"), "4")
        XCTAssertEqual(AgentEvalScoring.answerText(from: "<think>a</think>\n<think>b</think>It is 391."), "It is 391.")
        XCTAssertEqual(AgentEvalScoring.answerText(from: "<think>cut off while thinking"), "")
        XCTAssertEqual(AgentEvalScoring.answerText(from: "<think>a</think>Partial<think>cut"), "Partial")
        XCTAssertEqual(AgentEvalScoring.answerText(from: "  plain  "), "plain")
    }

    func testContainsIgnoresCaseAndAccentsAndTakesAlternatives() {
        XCTAssertTrue(AgentEvalScoring.contains("Mon Toán first", "toán"))
        XCTAssertTrue(AgentEvalScoring.contains("mon toan first", "toán"))
        XCTAssertTrue(AgentEvalScoring.contains("It is 1,200.", "1200|1.200|1,200"))
        XCTAssertFalse(AgentEvalScoring.contains("It is 1300.", "1200|1.200|1,200"))
        let year = String(Calendar.current.component(.year, from: Date()))
        XCTAssertTrue(AgentEvalScoring.contains("It is \(year).", "{year}"))
    }

    private func call(_ name: String, _ arguments: String) -> ToolCall { ToolCall(id: UUID().uuidString, name: name, argumentsJSON: arguments) }

    func testARightCallAndAnswerScoreFully() throws {
        let item = try caseNamed("calc-times-en")
        let outcome = AgentToolOutcome(calls: [call("calculator", #"{"expression":"17*23"}"#)], answer: "It is 391.", rounds: 2, seconds: 1.5)
        let score = AgentEvalScoring.score(item, outcome, includeAnswer: true)
        XCTAssertTrue(score.toolCorrect)
        XCTAssertEqual(score.argsParsed, true)
        XCTAssertNil(score.argsRight, "this case asks for no argument text")
        XCTAssertTrue(score.answerPassed)
        XCTAssertEqual(score.wrongToolCalls, 0)
        XCTAssertEqual(score.rounds, 2)
        XCTAssertEqual(score.answer, "It is 391.")
        XCTAssertNil(AgentEvalScoring.score(item, outcome, includeAnswer: false).answer, "a private model's answer is not kept")
    }

    func testAWrongToolIsCountedAndDoesNotCountAsChosen() throws {
        let item = try caseNamed("calc-times-en")
        let outcome = AgentToolOutcome(
            calls: [call("web_search", #"{"query":"17 times 23"}"#), call("calculator", #"{"expression":"17*23"}"#)], answer: "391")
        let score = AgentEvalScoring.score(item, outcome, includeAnswer: false)
        XCTAssertFalse(score.toolCorrect, "the first call decides")
        XCTAssertEqual(score.wrongToolCalls, 1)
        XCTAssertEqual(score.chosenTool, "web_search")
        XCTAssertTrue(score.answerPassed)
    }

    func testAnyCallOnAPromptThatNeedsNoToolIsWrong() throws {
        let item = try caseNamed("none-cats-en")
        let quiet = AgentEvalScoring.score(item, AgentToolOutcome(answer: "Cats purr."), includeAnswer: false)
        XCTAssertTrue(quiet.toolCorrect)
        XCTAssertNil(quiet.argsParsed)
        let noisy = AgentEvalScoring.score(
            item, AgentToolOutcome(calls: [call("current_date_time", "{}")], answer: "Cats purr."), includeAnswer: false)
        XCTAssertFalse(noisy.toolCorrect)
        XCTAssertEqual(noisy.wrongToolCalls, 1)
    }

    func testArgumentsThatAreNotJSONOrLackTheirKeyAreNotParsed() throws {
        let item = try caseNamed("calc-times-en")
        for arguments in ["{'expression': '2+2'}", "{}", #"{"expression":""}"#, "[1]"] {
            let score = AgentEvalScoring.score(item, AgentToolOutcome(calls: [call("calculator", arguments)], answer: "391"), includeAnswer: false)
            XCTAssertEqual(score.argsParsed, false, arguments)
        }
        let clock = try caseNamed("time-en")
        XCTAssertEqual(
            AgentEvalScoring.score(clock, AgentToolOutcome(calls: [call("current_date_time", "")], answer: "12:30"), includeAnswer: false).argsParsed, true,
            "the clock needs no argument")
    }

    func testACallLeftAsTextIsAnAttemptThatDidNotParse() throws {
        let item = try caseNamed("calc-times-en")
        let score = AgentEvalScoring.score(
            item, AgentToolOutcome(answer: "<tool_call>{'name': 'calculator'}</tool_call>", unparsedCallText: true), includeAnswer: false)
        XCTAssertEqual(score.argsParsed, false)
        XCTAssertFalse(score.toolCorrect)
        XCTAssertTrue(AgentEvalScoring.hasCallText("x <tool_call> y"))
        XCTAssertFalse(AgentEvalScoring.hasCallText("a plain answer"))
    }

    func testAFetchWithTheWrongURLIsNotRight() throws {
        let item = try caseNamed("fetch-changelog-en")
        let right = AgentEvalScoring.score(
            item, AgentToolOutcome(calls: [call("fetch_url", #"{"url":"https://zorblax.example/changelog"}"#)], answer: "4.2.1"), includeAnswer: false)
        XCTAssertEqual(right.argsRight, true)
        let wrong = AgentEvalScoring.score(
            item, AgentToolOutcome(calls: [call("fetch_url", #"{"url":"https://other.example/x"}"#)], answer: "4.2.1"), includeAnswer: false)
        XCTAssertEqual(wrong.argsRight, false)
        XCTAssertTrue(wrong.answerPassed, "the answer alone cannot tell, which is why the URL is checked apart")
    }

    func testAStreamFailureFailsTheAnswer() throws {
        let item = try caseNamed("calc-times-en")
        let score = AgentEvalScoring.score(item, AgentToolOutcome(answer: "391", failure: "boom"), includeAnswer: false)
        XCTAssertFalse(score.answerPassed)
        XCTAssertEqual(score.failure, "boom")
    }

    func testMustNotContainFailsAnAnswerThatNamesACity() throws {
        let item = try caseNamed("time-en")
        XCTAssertTrue(AgentEvalScoring.score(item, AgentToolOutcome(calls: [call("current_date_time", "{}")], answer: "It is 12:30."), includeAnswer: false).answerPassed)
        XCTAssertFalse(
            AgentEvalScoring.score(item, AgentToolOutcome(calls: [call("current_date_time", "{}")], answer: "It is 12:30 in Hanoi."), includeAnswer: false).answerPassed)
    }

    func testSummaryAndTheReportLine() {
        func score(_ id: String, correct: Bool, parsed: Bool?, passed: Bool, wrong: Int, rounds: Int?) -> AgentToolScore {
            AgentToolScore(
                id: id, language: "en", expectedTool: nil, chosenTool: nil, toolCorrect: correct, argsParsed: parsed, argsRight: nil,
                answerPassed: passed, wrongToolCalls: wrong, calls: 0, rounds: rounds, seconds: 1, failure: nil, answer: nil)
        }
        let scores = [
            score("a", correct: true, parsed: true, passed: true, wrong: 0, rounds: 2),
            score("b", correct: false, parsed: false, passed: false, wrong: 2, rounds: 3),
            score("c", correct: true, parsed: nil, passed: true, wrong: 0, rounds: 1),
        ]
        let summary = AgentEvalScoring.summarize(scores, total: 4)
        XCTAssertEqual(summary.ran, 3)
        XCTAssertEqual(summary.toolCorrect, 2)
        XCTAssertEqual(summary.withCalls, 2)
        XCTAssertEqual(summary.argsParsed, 1)
        XCTAssertEqual(summary.answerPassed, 2)
        XCTAssertEqual(summary.wrongToolCalls, 2)
        XCTAssertEqual(summary.roundsMax, 3)
        XCTAssertEqual(
            AgentEvalScoring.toolLine(summary, engine: "GGUF, test"),
            "agent eval tools (GGUF, test): ran 3/4, tool chosen 2/3, arguments parsed 1/2, arguments right 0/0, answers passed 2/3, "
                + "wrong tool calls 2, rounds 2.0 avg, 3 max, not run 1 (time cap)")
        let apple = AgentEvalScoring.summarize([score("a", correct: true, parsed: true, passed: true, wrong: 0, rounds: nil)], total: 1)
        XCTAssertTrue(AgentEvalScoring.toolLine(apple, engine: "Apple").hasSuffix("rounds n/a"))
    }

    // MARK: Report

    func testReportKeepsEverySectionAndRewritesOne() throws {
        let path = makeTempDirectory().appending(path: "agent-eval.json").path
        try AgentEvalReport.write("tools", AgentToolSummary(cases: 20, ran: 20), to: path)
        try AgentEvalReport.write("memory", ["recall": 5], to: path)
        try AgentEvalReport.write("tools", AgentToolSummary(cases: 20, ran: 7), to: path)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path))) as? [String: Any])
        XCTAssertEqual((root["tools"] as? [String: Any])?["ran"] as? Int, 7)
        XCTAssertEqual((root["memory"] as? [String: Any])?["recall"] as? Int, 5)
        try AgentEvalReport.write("tools", AgentToolSummary(), to: nil)
    }

    func testTheDeadlineStopsASet() {
        let now = Date()
        let deadline = EvalDeadline(minutes: 1, from: now)
        XCTAssertFalse(deadline.passed(at: now.addingTimeInterval(59)))
        XCTAssertTrue(deadline.passed(at: now.addingTimeInterval(60)))
    }

    // MARK: The harness end to end, on a scripted model

    /// Writes a Qwen-style call in round one and the answer in round two.
    private struct ScriptedEvalEngine: ChatEngine {
        let replies: [String]
        var source: ModelSource { .gguf }
        func availableModels() async throws -> [ModelDescriptor] { [] }
        func stream(model: ModelDescriptor, messages: [ChatMessage], params: GenerationParams) -> AsyncThrowingStream<ChatDelta, Error> {
            let reply = replies[min((messages.count - 1) / 2, replies.count - 1)]
            return AsyncThrowingStream { continuation in
                continuation.yield(.text(reply))
                continuation.yield(.done(finishReason: "stop"))
                continuation.finish()
            }
        }
    }

    func testTheRealLoopRunsACallAndTheHarnessScoresIt() async throws {
        let item = try caseNamed("calc-times-en")
        let call = "<tool_call>\n{\"name\": \"calculator\", \"arguments\": {\"expression\": \"17 * 23\"}}\n</tool_call>"
        let counter = EvalRoundCounter()
        let base = EvalCountingEngine(base: ScriptedEvalEngine(replies: [call, "It is 391."]), counter: counter)
        let engine = LocalToolEngine(wrapping: base, isEnabled: { true })
        let outcome = await AgentToolEvalRunner.run(item, engine: engine, model: qwen, rounds: counter, approver: EvalApprover())
        XCTAssertNil(outcome.failure)
        XCTAssertEqual(outcome.calls.map(\.name), ["calculator"])
        XCTAssertEqual(outcome.rounds, 2, "one generation for the call and one for the answer")
        let score = AgentEvalScoring.score(item, outcome, includeAnswer: false)
        XCTAssertTrue(score.toolCorrect)
        XCTAssertEqual(score.argsParsed, true)
        XCTAssertTrue(score.answerPassed, outcome.answer)

        let plain = try caseNamed("none-cats-en")
        let quiet = await AgentToolEvalRunner.run(
            plain, engine: LocalToolEngine(wrapping: EvalCountingEngine(base: ScriptedEvalEngine(replies: ["Cats purr."]), counter: counter), isEnabled: { true }),
            model: qwen, rounds: counter, approver: EvalApprover())
        XCTAssertEqual(quiet.rounds, 1, "the counter starts again for each case")
        XCTAssertTrue(AgentEvalScoring.score(plain, quiet, includeAnswer: false).answerPassed)
    }
}
