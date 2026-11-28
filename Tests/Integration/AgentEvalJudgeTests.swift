import XCTest

@testable import AnyRouter

/// The memory judge without a network: the request it sends, how it reads an answer, the two runs and their spread, and the
/// whole set run with a stub judge and a stub model.
private final class JudgeBodies: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [Data] = []
    var all: [Data] { lock.withLock { stored } }
    func add(_ body: Data) { lock.withLock { stored.append(body) } }
}

private enum JudgeStubs {
    static func response(_ used: Int, _ invented: Int) -> Data {
        let content = "{\"used_right_memory\": \(used), \"invented_memory\": \(invented)}"
        let object: [String: Any] = ["choices": [["message": ["content": content]]]]
        return (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    }

    static func userContent(_ body: Data) -> String {
        guard let root = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
            let messages = root["messages"] as? [[String: Any]], let user = messages.last?["content"] as? String
        else { return "" }
        return user
    }

    static let reversedEnding = "{\"invented_memory\": <0-5>, \"used_right_memory\": <0-5>}"

    /// 5 and 0 on the first run, 3 and 1 on the second (the one that asks for the keys in the other order).
    static func stub(_ bodies: JudgeBodies = JudgeBodies()) -> AgentJudgeSetup {
        AgentJudgeSetup(model: "judge-model") { body in
            bodies.add(body)
            return userContent(body).hasSuffix(reversedEnding) ? response(3, 1) : response(5, 0)
        }
    }
}

final class AgentEvalJudgeTests: XCTestCase {
    // MARK: Choosing

    func testTheJudgeRunsOnlyWithAKeyAndNeverForAModelGivenAtRunTime() {
        func reason(_ choice: AgentJudgeChoice) -> String? {
            if case .skipped(let text) = choice { return text }
            return nil
        }
        XCTAssertEqual(reason(AgentEvalJudge.choice(key: "k", external: true, base: nil, model: nil)), "judge skipped, model given at run time")
        XCTAssertEqual(
            reason(AgentEvalJudge.choice(key: nil, external: false, base: nil, model: nil)), "judge skipped, ANYROUTER_E2E_API_KEY is not set")
        XCTAssertEqual(
            reason(AgentEvalJudge.choice(key: "", external: false, base: nil, model: nil)), "judge skipped, ANYROUTER_E2E_API_KEY is not set")
        guard case .run(let setup) = AgentEvalJudge.choice(key: "k", external: false, base: "", model: "") else {
            return XCTFail("a key runs the judge")
        }
        XCTAssertEqual(setup.model, "anyrouter/auto")
        guard case .run(let custom) = AgentEvalJudge.choice(key: "k", external: false, base: "https://example.test/v1", model: "other/model") else {
            return XCTFail("a key runs the judge")
        }
        XCTAssertEqual(custom.model, "other/model")
    }

    // MARK: Asking and reading

    func testTheRequestIsTemperatureZeroJSONWithTheReplyInIt() throws {
        let body = try AgentEvalJudge.requestBody(model: "m", user: "hello")
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(root["model"] as? String, "m")
        XCTAssertEqual(root["temperature"] as? Int, 0)
        XCTAssertEqual((root["response_format"] as? [String: String])?["type"], "json_object")
        XCTAssertEqual((root["messages"] as? [[String: Any]])?.count, 2)
        XCTAssertEqual(JudgeStubs.userContent(body), "hello")
    }

    func testTheSecondRunAsksForTheCriteriaInTheOtherOrder() {
        let first = AgentEvalJudge.userPrompt(question: "Q", shown: ["A"], right: "R", reply: "ANS", reversed: false)
        let second = AgentEvalJudge.userPrompt(question: "Q", shown: ["A"], right: "R", reply: "ANS", reversed: true)
        XCTAssertNotEqual(first, second)
        XCTAssertTrue(first.contains("The user asked: Q"))
        XCTAssertTrue(first.contains("The assistant replied: ANS"))
        XCTAssertTrue(first.contains("Notes shown to the assistant before the question: A"))
        XCTAssertTrue(AgentEvalJudge.userPrompt(question: "Q", shown: [], right: "R", reply: "ANS", reversed: false).contains("before the question: none"))
        let usedFirst = first.range(of: "used_right_memory: 5")?.lowerBound
        let inventedFirst = first.range(of: "invented_memory: 0")?.lowerBound
        let usedSecond = second.range(of: "used_right_memory: 5")?.lowerBound
        let inventedSecond = second.range(of: "invented_memory: 0")?.lowerBound
        XCTAssertTrue(try XCTUnwrap(usedFirst) < XCTUnwrap(inventedFirst))
        XCTAssertTrue(try XCTUnwrap(inventedSecond) < XCTUnwrap(usedSecond))
        XCTAssertTrue(second.hasSuffix(JudgeStubs.reversedEnding))
    }

    func testAVerdictIsReadFromTheAnswerAndRejectedWhenBroken() {
        XCTAssertEqual(AgentEvalJudge.verdict(from: JudgeStubs.response(4, 1)), AgentJudgeVerdict(usedRightMemory: 4, inventedMemory: 1))
        let fenced: [String: Any] = ["choices": [["message": ["content": "Here:\n" + "```json\n{\"used_right_memory\": 2, \"invented_memory\": 5}\n" + "```"]]]]
        XCTAssertEqual(
            AgentEvalJudge.verdict(from: (try? JSONSerialization.data(withJSONObject: fenced)) ?? Data()),
            AgentJudgeVerdict(usedRightMemory: 2, inventedMemory: 5), "JSON inside a code fence is read")
        XCTAssertNil(AgentEvalJudge.verdict(from: JudgeStubs.response(6, 0)), "a score above 5")
        XCTAssertNil(AgentEvalJudge.verdict(from: JudgeStubs.response(0, -1)), "a score below 0")
        XCTAssertNil(AgentEvalJudge.verdict(from: Data("not json".utf8)))
        XCTAssertNil(AgentEvalJudge.verdict(from: Data("{\"choices\": []}".utf8)))
        let missing: [String: Any] = ["choices": [["message": ["content": "{\"used_right_memory\": 3}"]]]]
        XCTAssertNil(AgentEvalJudge.verdict(from: (try? JSONSerialization.data(withJSONObject: missing)) ?? Data()))
    }

    func testTwoRunsGoOutAndComeBackInOrder() async throws {
        let bodies = JudgeBodies()
        let runs = try await AgentEvalJudge.judge(question: "Q", shown: [], right: "R", reply: "ANS", setup: JudgeStubs.stub(bodies))
        XCTAssertEqual(runs, [AgentJudgeVerdict(usedRightMemory: 5, inventedMemory: 0), AgentJudgeVerdict(usedRightMemory: 3, inventedMemory: 1)])
        XCTAssertEqual(bodies.all.count, 2)
        XCTAssertFalse(JudgeStubs.userContent(bodies.all[0]).hasSuffix(JudgeStubs.reversedEnding))
        XCTAssertTrue(JudgeStubs.userContent(bodies.all[1]).hasSuffix(JudgeStubs.reversedEnding))
    }

    func testAnUnreadableAnswerThrows() async {
        let broken = AgentJudgeSetup(model: "m") { _ in Data("nope".utf8) }
        do {
            _ = try await AgentEvalJudge.judge(question: "Q", shown: [], right: "R", reply: "A", setup: broken)
            XCTFail("an unreadable answer must throw")
        } catch {
            XCTAssertEqual(error as? AgentJudgeError, .unreadable)
        }
    }

    // MARK: Reporting

    func testMeansAndTheSpreadBetweenTheTwoRuns() {
        let results = [
            AgentJudgeResult(id: "a", runs: [AgentJudgeVerdict(usedRightMemory: 5, inventedMemory: 0), AgentJudgeVerdict(usedRightMemory: 3, inventedMemory: 1)]),
            AgentJudgeResult(id: "b", runs: [AgentJudgeVerdict(usedRightMemory: 4, inventedMemory: 2), AgentJudgeVerdict(usedRightMemory: 4, inventedMemory: 2)]),
        ]
        let summary = AgentEvalJudge.summarize(results, failed: 1)
        XCTAssertEqual(summary.judged, 2)
        XCTAssertEqual(summary.failed, 1)
        XCTAssertEqual(summary.usedMean, 4.0)
        XCTAssertEqual(summary.usedSpread, 1.0, "case a differs by 2, case b by 0")
        XCTAssertEqual(summary.inventedMean, 1.25)
        XCTAssertEqual(summary.inventedSpread, 0.5)
        XCTAssertEqual(
            AgentEvalJudge.line(summary, model: "m"),
            "judge m on 2 replies: used the right memory 4.0/5 (spread between the two runs 1.0), invented a memory 1.25/5 (spread 0.5), 1 replies not judged")
        XCTAssertEqual(AgentEvalJudge.summarize([], failed: 0), AgentJudgeSummary())
    }

    // MARK: The whole set, on stubs

    func testTheSetRunsEveryPromptThroughAStubModelAndAStubJudge() async throws {
        let model = ModelDescriptor(
            id: "gguf/test", source: .gguf, displayName: "Test", contextLength: 262_144, capabilities: [], sizeBytes: nil, isInstalled: true)
        let replies = JudgeBodies()
        let generate: AgentMemoryGenerator = { messages in
            replies.add(Data((messages.last?.content ?? "").utf8))
            return "A reply."
        }
        let result = try await AgentMemoryEvalRunner.runSet(
            try AgentEvalFixtures.memoryCases(), model: model, label: "stub", section: "memory", generate: generate,
            judge: .run(JudgeStubs.stub()))
        XCTAssertEqual(replies.all.count, 10, "the model wrote a reply for every prompt, from the assembled request")
        XCTAssertTrue(String(decoding: replies.all[0], as: UTF8.self).hasPrefix(MemoryRecallLogic.heading), "the first reply saw its recalled memories")
        let judged = try XCTUnwrap(result.judgeSummary)
        XCTAssertEqual(judged.judged, 10)
        XCTAssertEqual(judged.failed, 0)
        XCTAssertEqual(judged.usedMean, 4.0)
        XCTAssertEqual(judged.usedSpread, 2.0)
        XCTAssertTrue(try XCTUnwrap(result.lines.first).contains("judge judge-model on 10 replies"))
    }

    func testAReplyTheJudgeCannotReadIsCountedNotHidden() async throws {
        let model = ModelDescriptor(
            id: "gguf/test", source: .gguf, displayName: "Test", contextLength: 262_144, capabilities: [], sizeBytes: nil, isInstalled: true)
        let flaky = AgentJudgeSetup(model: "judge-model") { body in
            String(decoding: body, as: UTF8.self).contains("Hachiko") ? Data("nope".utf8) : JudgeStubs.response(5, 0)
        }
        let result = try await AgentMemoryEvalRunner.runSet(
            try AgentEvalFixtures.memoryCases(), model: model, label: "stub", section: "memory", generate: { _ in "A reply." }, judge: .run(flaky))
        let judged = try XCTUnwrap(result.judgeSummary)
        XCTAssertEqual(judged.judged, 9)
        XCTAssertEqual(judged.failed, 1)
        XCTAssertTrue(try XCTUnwrap(result.lines.first).contains("1 replies not judged"))
    }

    func testAJudgeWithoutAModelSaysSo() async throws {
        let model = ModelDescriptor(
            id: "gguf/test", source: .gguf, displayName: "Test", contextLength: 262_144, capabilities: [], sizeBytes: nil, isInstalled: true)
        let result = try await AgentMemoryEvalRunner.runSet(
            try AgentEvalFixtures.memoryCases(), model: model, label: "stub", section: "memory", generate: nil, judge: .run(JudgeStubs.stub()))
        XCTAssertEqual(result.judge, "judge skipped, this engine has no reply generator")
    }

    func testTheRightMemoryTextForTheJudge() throws {
        let cases = try AgentEvalFixtures.memoryCases()
        let mochi = try XCTUnwrap(cases.first { $0.id == "recall-mochi-treats" })
        XCTAssertEqual(AgentMemoryEvalRunner.rightMemory(for: mochi), "My dog is called Mochi; Mochi is allergic to chicken")
        let trap = try XCTUnwrap(cases.first { $0.kind == "trap" })
        XCTAssertTrue(AgentMemoryEvalRunner.rightMemory(for: trap).hasPrefix("none"))
        let save = try XCTUnwrap(cases.first { $0.kind == "save" })
        XCTAssertTrue(AgentMemoryEvalRunner.rightMemory(for: save).contains(try XCTUnwrap(save.saved)))
    }
}
