import XCTest

@testable import AnyRouter

/// LA11 on a real GGUF model (PLAN D28 unit L1): the tool-calling set through the real `GGUFEngine`, the app's
/// `LocalToolEngine` and the app's tool loop (`AgentLoop`). The clock and the calculator are the real tools; web search and
/// the page reader answer fixed text (see `agent-tool-evals.json`). It reports numbers and never fails on the model's
/// skill: a small model that picks the wrong tool is a finding, not a broken harness. Runs in model-smoke.yml only.
final class AgentToolEvalSmokeTests: XCTestCase {
    func testToolCallingSetThroughTheRealEngineAndLoop() async throws {
        let ctx = try await GGUFModelSmokeTests.makeContext()
        let label = SmokeEnv.external ? "GGUF, model given at run time" : "GGUF, \(ctx.entry.title) \(ctx.entry.quantization ?? "")"
        guard LocalToolFormat.detect(for: ctx.model) != nil else {
            let note = "agent eval tools (\(label)): skipped, this model's family has no tool format, so the app gives it no tools"
            AgentEvalReport.publish(note)
            SmokeReport.record("Agent eval tools", "SKIPPED, the model's family has no tool format")
            throw XCTSkip(note)
        }
        let cases = try AgentEvalFixtures.toolCases()
        let counter = EvalRoundCounter()
        let engine = LocalToolEngine(wrapping: EvalCountingEngine(base: ctx.engine, counter: counter), isEnabled: { true })
        let result = try await AgentToolEvalRunner.runSet(cases, engine: engine, model: ctx.model, rounds: counter, label: label, section: "tools")

        XCTAssertFalse(result.cases.isEmpty, "no case ran inside the time cap")
        XCTAssertLessThan(result.summary.failed, max(result.summary.ran, 1), "every stream failed, so the harness is broken, not the model")
        for score in result.cases {
            let parsed = score.argsParsed.map { $0 ? "yes" : "no" } ?? "n/a"
            let rounds = score.rounds.map { "\($0)" } ?? "n/a"
            let seconds = String(format: "%.1f s", score.seconds)
            let tool = "tool \(score.chosenTool ?? "none") (want \(score.expectedTool ?? "none")), arguments parsed \(parsed)"
            let answer = "answer \(score.answerPassed ? "passed" : "failed"), wrong calls \(score.wrongToolCalls), rounds \(rounds), \(seconds)"
            SmokeReport.record("Agent eval \(score.id)", tool + ", " + answer)
        }
    }
}

/// The memory set (agent design 5.2) on the real model's budget: each prompt's request is built the way the chat builds it,
/// and the scripted checks say whether the right memory was in it. Reports numbers; asserts only that the harness ran.
final class AgentMemoryEvalSmokeTests: XCTestCase {
    func testMemorySetRequestsOnTheRealModel() async throws {
        let ctx = try await GGUFModelSmokeTests.makeContext()
        let label = SmokeEnv.external ? "GGUF, model given at run time" : "GGUF, \(ctx.entry.title) \(ctx.entry.quantization ?? "")"
        let cases = try AgentEvalFixtures.memoryCases()
        let result = try AgentMemoryEvalRunner.runSet(cases, model: ctx.model, label: label, section: "memory")
        XCTAssertEqual(result.cases.count, cases.count, "every prompt got a request")
    }
}
