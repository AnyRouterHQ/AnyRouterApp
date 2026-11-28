import XCTest

@testable import AnyRouter

/// The scripted half of the memory set, in main CI for every model source: what is in each request, and the report line.
final class AgentMemoryEvalSupportTests: XCTestCase {
    private func descriptor(_ source: ModelSource, context: Int?) -> ModelDescriptor {
        ModelDescriptor(
            id: "\(source.rawValue)/test", source: source, displayName: "Test", contextLength: context, capabilities: [], sizeBytes: nil,
            isInstalled: true)
    }

    private var models: [(String, ModelDescriptor)] {
        [("apple", descriptor(.apple, context: 4096)), ("gguf", descriptor(.gguf, context: 262_144)),
         ("mlx", descriptor(.mlx, context: 32_768)), ("anyrouter", descriptor(.anyrouter, context: nil))]
    }

    func testFixtureIsFiveRecallThreeTrapsTwoSavesOverTheThirtyMemories() throws {
        let cases = try AgentEvalFixtures.memoryCases()
        XCTAssertEqual(cases.count, 10)
        XCTAssertEqual(Set(cases.map(\.id)).count, 10)
        XCTAssertEqual(cases.filter { $0.kind == "recall" }.count, 5)
        XCTAssertEqual(cases.filter { $0.kind == "trap" }.count, 3)
        XCTAssertEqual(cases.filter { $0.kind == "save" }.count, 2)
        XCTAssertEqual(MemoryRecallEvalTests.memories.count, 30)
        let size = MemoryRecallEvalTests.memories.count
        for item in cases {
            XCTAssertTrue((item.want + item.forbid).allSatisfy { (0..<size).contains($0) }, "\(item.id): an index outside the 30 memories")
            switch item.kind {
            case "recall": XCTAssertFalse(item.want.isEmpty, item.id)
            case "trap": XCTAssertFalse(item.forbid.isEmpty, item.id)
            default: XCTAssertNotNil(item.saved, item.id); XCTAssertNotNil(item.thenAsk, item.id)
            }
        }
        XCTAssertEqual(Set(cases.map(\.language)), ["en", "vi"])
    }

    func testTheRightMemoryIsInTheRequestOfEveryRecallPromptOnEverySource() throws {
        for (name, model) in models {
            for item in try AgentEvalFixtures.memoryCases() where item.kind == "recall" {
                let run = AgentMemoryScripted.run(item, model: model)
                XCTAssertEqual(run.script.rightInRequest, true, "\(name) \(item.id): recalled \(run.script.recalled)")
                let last = try XCTUnwrap(run.prompt.messages.last)
                XCTAssertEqual(last.role, .user)
                XCTAssertTrue(last.content.hasSuffix(item.prompt), "the memories come before the question")
                XCTAssertTrue(last.content.hasPrefix(MemoryRecallLogic.heading), "\(name) \(item.id)")
            }
        }
    }

    func testAnExplicitSaveIsKeptAndFoundAgainOnEverySource() throws {
        for (name, model) in models {
            for item in try AgentEvalFixtures.memoryCases() where item.kind == "save" {
                XCTAssertEqual(AgentMemoryScripted.run(item, model: model).script.saved, true, "\(name) \(item.id)")
            }
        }
    }

    func testATrapIsCountedWhenItsLookalikeIsRecalled() throws {
        let trap = AgentMemoryCase(
            id: "t", kind: "trap", language: "en", prompt: "How do I train a neural network?", want: [], forbid: [15], saved: nil, thenAsk: nil)
        let run = AgentMemoryScripted.run(trap, model: descriptor(.gguf, context: 262_144))
        XCTAssertEqual(run.script.recalled, [15], "BM25 has no score floor, so the shared word \"train\" recalls the trains memory")
        XCTAssertEqual(run.script.wrongRecalls, 1)
        let clean = AgentMemoryCase(
            id: "c", kind: "trap", language: "en", prompt: "Explain quantum entanglement", want: [], forbid: [15], saved: nil, thenAsk: nil)
        let none = AgentMemoryScripted.run(clean, model: descriptor(.gguf, context: 262_144))
        XCTAssertEqual(none.script.wrongRecalls, 0)
        XCTAssertEqual(none.prompt.messages.last?.content, "Explain quantum entanglement", "no memory, no block")
    }

    func testAMissedWantedMemoryShowsAsNotRight() {
        let miss = AgentMemoryCase(
            id: "m", kind: "recall", language: "en", prompt: "Suggest a dinner recipe for tonight", want: [2], forbid: [], saved: nil, thenAsk: nil)
        let run = AgentMemoryScripted.run(miss, model: descriptor(.gguf, context: 262_144))
        XCTAssertEqual(run.script.found, 0, "\"dinner\" shares no word with \"I am vegetarian\": the case that needs meaning")
        XCTAssertEqual(run.script.rightInRequest, false)
    }

    func testSummaryAndTheReportLine() {
        func script(_ kind: String, found: Int = 0, wanted: Int = 0, right: Bool? = nil, wrong: Int = 0, saved: Bool? = nil) -> AgentMemoryScript {
            AgentMemoryScript(id: kind, kind: kind, recalled: [], found: found, wanted: wanted, rightInRequest: right, wrongRecalls: wrong, saved: saved)
        }
        let scripts = [
            script("recall", found: 2, wanted: 2, right: true), script("recall", found: 0, wanted: 1, right: false, wrong: 1),
            script("trap", wrong: 2), script("trap"), script("save", saved: true), script("save", saved: false),
        ]
        let summary = AgentMemoryScripted.summarize(scripts, total: 6)
        XCTAssertEqual(summary.recallFound, 2)
        XCTAssertEqual(summary.recallWanted, 3)
        XCTAssertEqual(summary.recallRight, 1)
        XCTAssertEqual(summary.wrongRecalls, 3)
        XCTAssertEqual(summary.scoredPrompts, 4)
        XCTAssertEqual(summary.trapHit, 1)
        XCTAssertEqual(summary.savesKept, 1)
        XCTAssertEqual(
            AgentMemoryScripted.line(summary, engine: "Apple", judge: "judge skipped"),
            "agent eval memory (Apple): recall at 3 2/3 (every wanted memory in the request for 1/2 recall prompts), "
                + "wrong recalls 3 in 4 prompts (1/2 trap prompts recalled a trap memory), "
                + "extraction precision 1/2 explicit saves kept and found again, judge skipped")
    }

    /// The numbers of the scripted half for every source, in the log where the CI step "Measurement reports" finds them.
    func testReportsTheScriptedNumbersForEverySource() throws {
        let cases = try AgentEvalFixtures.memoryCases()
        for (name, model) in models {
            let scripts = cases.map { AgentMemoryScripted.run($0, model: model).script }
            let summary = AgentMemoryScripted.summarize(scripts, total: cases.count)
            AgentEvalReport.publish(AgentMemoryScripted.line(summary, engine: "scripted, \(name) budget", judge: "no model"))
            XCTAssertEqual(summary.recallFound, summary.recallWanted, name)
        }
    }

    func testRunSetWritesItsSection() throws {
        let path = makeTempDirectory().appending(path: "agent-eval.json").path
        let cases = try AgentEvalFixtures.memoryCases()
        let scripts = cases.map { AgentMemoryScripted.run($0, model: descriptor(.gguf, context: 262_144)).script }
        let summary = AgentMemoryScripted.summarize(scripts, total: cases.count)
        let section = AgentMemorySection(
            engine: "test", summary: summary, cases: scripts, lines: [AgentMemoryScripted.line(summary, engine: "test", judge: "no model")])
        try AgentEvalReport.write("memory", section, to: path)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path))) as? [String: Any])
        let written = try XCTUnwrap(root["memory"] as? [String: Any])
        XCTAssertEqual((written["cases"] as? [Any])?.count, 10)
        XCTAssertEqual((written["lines"] as? [String])?.first?.hasPrefix("agent eval memory (test)"), true)
    }
}
