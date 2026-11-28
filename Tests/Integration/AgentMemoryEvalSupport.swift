import Foundation
import XCTest

@testable import AnyRouter

// The memory set of the live agent eval (agent design 5.2 and 5.3, unit L1): 10 prompts over the 30 memories of
// MemoryRecallEvalTests. The scripted half builds each request the way the chat does (recall, then PromptAssembler) and
// checks what is in it. It needs no model, so it also runs in main CI for every model source.

struct AgentMemoryCase: Decodable, Sendable, Equatable {
    var id: String
    /// "recall", "trap" or "save".
    var kind: String
    var language: String
    var prompt: String
    /// Indexes into MemoryRecallEvalTests.memories that the request should hold.
    var want: [Int]
    /// Indexes of memories that look similar and must stay out of the request.
    var forbid: [Int]
    /// A save case: the text RememberLogic should keep.
    var saved: String?
    /// A save case: a later question that should find the saved text.
    var thenAsk: String?
}

struct AgentMemoryFile: Decodable {
    var note: String
    var cases: [AgentMemoryCase]
}

extension AgentEvalFixtures {
    static func memoryCases() throws -> [AgentMemoryCase] {
        try JSONDecoder().decode(AgentMemoryFile.self, from: data("agent-memory-evals")).cases
    }
}

/// What the scripted half found for one prompt.
struct AgentMemoryScript: Codable, Equatable, Sendable {
    var id: String
    var kind: String
    /// Indexes of the memories recalled for the prompt, best first.
    var recalled: [Int]
    /// recall: wanted memories found in the request, and how many were wanted.
    var found: Int
    var wanted: Int
    /// recall: every wanted memory is in the request. Nil for the other kinds.
    var rightInRequest: Bool?
    /// recall: memories nobody wanted. trap: forbidden memories that were recalled.
    var wrongRecalls: Int
    /// save: the text was kept as an explicit save and a later question finds it. Nil for the other kinds.
    var saved: Bool?
}

struct AgentMemorySummary: Codable, Equatable, Sendable {
    var cases = 0
    var recallCases = 0
    var recallWanted = 0
    var recallFound = 0
    var recallRight = 0
    var scoredPrompts = 0
    var wrongRecalls = 0
    var trapCases = 0
    var trapHit = 0
    var saveCases = 0
    var savesKept = 0
}

enum AgentMemoryScripted {
    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
    }

    /// The request the chat would send for `item.prompt` on `model`, and what the scripted checks say about it.
    static func run(_ item: AgentMemoryCase, model: ModelDescriptor) -> (script: AgentMemoryScript, prompt: AssembledPrompt) {
        let pool = MemoryRecallEvalTests.candidates
        let budget = PromptBudget.forModel(model).memoryHits
        let hits = MemoryRecallLogic.recall(item.prompt, from: pool, budget: budget)
        let recalled = hits.compactMap { hit in pool.firstIndex { $0.id == hit.candidate.id } }
        let prompt = PromptAssembler.assemble(
            instructions: nil, profile: nil, summary: nil, turns: [ChatMessage(role: .user, content: item.prompt)],
            context: MemoryRecallLogic.block(hits))
        let request = prompt.messages.map(\.content).joined(separator: "\n")
        var script = AgentMemoryScript(
            id: item.id, kind: item.kind, recalled: recalled, found: 0, wanted: 0, rightInRequest: nil, wrongRecalls: 0, saved: nil)
        switch item.kind {
        case "recall":
            script.wanted = item.want.count
            script.found = item.want.filter { request.contains(pool[$0].text) }.count
            script.rightInRequest = script.found == script.wanted
            script.wrongRecalls = recalled.filter { !item.want.contains($0) }.count
        case "trap":
            script.wrongRecalls = recalled.filter { item.forbid.contains($0) }.count
        default:
            var kept = false
            if let candidate = RememberLogic.candidate(in: item.prompt), candidate.explicit, let saved = item.saved,
                fold(candidate.text) == fold(saved) {
                let extended = pool + [MemoryRecallLogic.Candidate(id: UUID(), text: candidate.text)]
                let later = MemoryRecallLogic.recall(item.thenAsk ?? "", from: extended, budget: budget)
                kept = later.contains { $0.candidate.text == candidate.text }
            }
            script.saved = kept
        }
        return (script, prompt)
    }

    static func summarize(_ scripts: [AgentMemoryScript], total: Int) -> AgentMemorySummary {
        let recall = scripts.filter { $0.kind == "recall" }
        let traps = scripts.filter { $0.kind == "trap" }
        let saves = scripts.filter { $0.kind == "save" }
        return AgentMemorySummary(
            cases: total, recallCases: recall.count, recallWanted: recall.reduce(0) { $0 + $1.wanted },
            recallFound: recall.reduce(0) { $0 + $1.found }, recallRight: recall.filter { $0.rightInRequest == true }.count,
            scoredPrompts: recall.count + traps.count, wrongRecalls: (recall + traps).reduce(0) { $0 + $1.wrongRecalls },
            trapCases: traps.count, trapHit: traps.filter { $0.wrongRecalls > 0 }.count,
            saveCases: saves.count, savesKept: saves.filter { $0.saved == true }.count)
    }

    /// The one-line report the workflow greps into the job summary. Metric names are agent design 5.3's.
    static func line(_ summary: AgentMemorySummary, engine: String, judge: String) -> String {
        "agent eval memory (\(engine)): recall at 3 \(summary.recallFound)/\(summary.recallWanted) "
            + "(every wanted memory in the request for \(summary.recallRight)/\(summary.recallCases) recall prompts), "
            + "wrong recalls \(summary.wrongRecalls) in \(summary.scoredPrompts) prompts "
            + "(\(summary.trapHit)/\(summary.trapCases) trap prompts recalled a trap memory), "
            + "extraction precision \(summary.savesKept)/\(summary.saveCases) explicit saves kept and found again, \(judge)"
    }
}

struct AgentMemorySection: Codable, Equatable, Sendable {
    var engine: String
    var summary: AgentMemorySummary
    var cases: [AgentMemoryScript]
    var lines: [String]
}

enum AgentMemoryEvalRunner {
    /// The whole set on `model`'s budget. Prints and records the report line and writes the JSON section.
    static func runSet(_ cases: [AgentMemoryCase], model: ModelDescriptor, label: String, section: String) throws -> AgentMemorySection {
        let scripts = cases.map { AgentMemoryScripted.run($0, model: model).script }
        let summary = AgentMemoryScripted.summarize(scripts, total: cases.count)
        let line = AgentMemoryScripted.line(summary, engine: label, judge: "judge not wired yet")
        let result = AgentMemorySection(engine: label, summary: summary, cases: scripts, lines: [line])
        AgentEvalReport.publish(line)
        SmokeReport.record("Agent eval memory (\(label))", String(line.drop { $0 != ":" }.dropFirst(2)))
        try AgentEvalReport.write(section, result)
        return result
    }
}
