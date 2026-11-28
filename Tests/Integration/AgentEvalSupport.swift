import Foundation
import XCTest

@testable import AnyRouter

// The live agent eval (PLAN D28 unit L1, agent design 5.2 and 5.3). This file holds what needs no model: the fixture, the
// tool host the cases run on, the scoring and the report. The smoke tests that load a model are in AgentEvalSmokeTests.

// MARK: Fixture

/// One prompt of the tool-calling set (PLAN LA11).
struct AgentToolCase: Decodable, Sendable, Equatable {
    var id: String
    /// "en" or "vi".
    var language: String
    var prompt: String
    /// The tool a good model calls first; nil when the prompt needs none.
    var expectTool: String?
    /// Text the arguments of the expected call must hold, like the URL the user wrote.
    var argsContain: [String]
    /// What the stub web_search or fetch_url answers. Nil for the clock, the calculator and no tool.
    var fixtureResult: String?
    /// Every entry must be in the answer, ignoring case and accents. "a|b" accepts either.
    var mustContain: [String]
    var mustNotContain: [String]
}

struct AgentToolFile: Decodable {
    var note: String
    var cases: [AgentToolCase]
}

private final class AgentEvalFixtureAnchor {}

enum AgentEvalFixtures {
    static func data(_ name: String) throws -> Data {
        let url = try XCTUnwrap(
            Bundle(for: AgentEvalFixtureAnchor.self).url(forResource: name, withExtension: "json"), "\(name).json is not in the test bundle")
        return try Data(contentsOf: url)
    }

    static func toolCases() throws -> [AgentToolCase] {
        try JSONDecoder().decode(AgentToolFile.self, from: data("agent-tool-evals")).cases
    }
}

// MARK: Tools

/// A web_search or fetch_url that answers one fixed text. The facts in it are invented, so an answer that has them
/// proves the model read the result.
struct EvalFixtureTool: BuiltInTool {
    let name: String
    let title: String
    let summary: String
    let description: String
    let schema: JSONSchema
    let result: String

    func run(_ arguments: JSONValue) async throws -> String { result }

    static func search(result: String) -> EvalFixtureTool {
        EvalFixtureTool(
            name: WebSearchBinding.name, title: "Search the web", summary: "Search the web", description: WebSearchBinding.description,
            schema: WebSearchBinding.schema, result: result)
    }

    static func pageReader(result: String) -> EvalFixtureTool {
        let real = FetchURLTool()
        return EvalFixtureTool(
            name: real.name, title: real.title, summary: real.summary, description: real.description,
            schema: real.schema, result: result)
    }
}

/// Allows every call the host asks about, and counts them. The host asks when a URL is not one the user wrote.
final class EvalApprover: ToolApproving, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var asked: Int { lock.withLock { count } }

    func decide(_ request: ToolApprovalRequest) async -> ToolDecision {
        lock.withLock { count += 1 }
        return .allowOnce
    }
}

enum AgentEvalHost {
    /// The app's host for a device model: four tools shaped by the model source's profile, with the guard that knows what
    /// the user wrote.
    static func make(for item: AgentToolCase, source: ModelSource, approver: EvalApprover) -> AgentToolHost {
        let fixture = item.fixtureResult ?? "No results."
        return AgentToolHost(
            builtIns: [CurrentDateTimeTool(), CalculatorTool(), EvalFixtureTool.search(result: fixture), EvalFixtureTool.pageReader(result: fixture)],
            search: nil, mcp: nil, approver: approver, exfiltration: ExfiltrationGuard(userTexts: [item.prompt]),
            profile: ToolProfile.forModel(source))
    }
}

// MARK: Counting rounds

/// Counts generations of the engine under the tool loop: one per round.
final class EvalRoundCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    var count: Int { lock.withLock { value } }
    func increment() { lock.withLock { value += 1 } }
    func reset() { lock.withLock { value = 0 } }
}

struct EvalCountingEngine: ChatEngine {
    let base: any ChatEngine
    let counter: EvalRoundCounter

    var source: ModelSource { base.source }

    func availableModels() async throws -> [ModelDescriptor] { try await base.availableModels() }

    func stream(model: ModelDescriptor, messages: [ChatMessage], params: GenerationParams) -> AsyncThrowingStream<ChatDelta, Error> {
        counter.increment()
        return base.stream(model: model, messages: messages, params: params)
    }
}

/// A wall-clock cap for one eval set: cases after it are reported as not run, so a slow model cannot hit the job's timeout.
struct EvalDeadline {
    let end: Date

    init(minutes: Double, from now: Date = Date()) { end = now.addingTimeInterval(minutes * 60) }

    func passed(at now: Date = Date()) -> Bool { now >= end }
}

// MARK: Scoring

struct AgentToolOutcome: Sendable {
    var calls: [ToolCall] = []
    /// The text after the thinking.
    var answer = ""
    /// Generations the engine ran; nil where the harness cannot count them (Apple runs its own loop).
    var rounds: Int?
    var seconds = 0.0
    /// The stream threw.
    var failure: String?
    /// The visible text holds a call the parser could not read.
    var unparsedCallText = false
}

struct AgentToolScore: Codable, Equatable, Sendable {
    var id: String
    var language: String
    var expectedTool: String?
    var chosenTool: String?
    /// The first call is the expected tool, or there is no call when none is expected.
    var toolCorrect: Bool
    /// Every call had a JSON object with its required argument. Nil when the model made no call and wrote none.
    var argsParsed: Bool?
    /// The expected call's arguments hold the text the case asks for. Nil when the case asks for none.
    var argsRight: Bool?
    var answerPassed: Bool
    var wrongToolCalls: Int
    var calls: Int
    var rounds: Int?
    var seconds: Double
    var failure: String?
    /// The start of the answer, kept for a model that is not private.
    var answer: String?
}

struct AgentToolSummary: Codable, Equatable, Sendable {
    var cases = 0
    var ran = 0
    var toolCorrect = 0
    var withCalls = 0
    var argsParsed = 0
    var argsChecked = 0
    var argsRight = 0
    var answerPassed = 0
    var wrongToolCalls = 0
    var roundsCount = 0
    var roundsTotal = 0
    var roundsMax = 0
    var failed = 0
}

enum AgentEvalScoring {
    /// The argument each tool needs.
    static let requiredArgument: [String: String] = ["calculator": "expression", "web_search": "query", "fetch_url": "url"]

    /// What follows the last </think>. Thinking that was cut off leaves no answer.
    static func answerText(from raw: String) -> String {
        var tail = Substring(raw)
        if let end = raw.range(of: "</think>", options: .backwards) { tail = raw[end.upperBound...] }
        if let open = tail.range(of: "<think>") { tail = tail[..<open.lowerBound] }
        return tail.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A call written in a family's format that the parser left as text.
    static func hasCallText(_ raw: String) -> Bool {
        ["<tool_call>", "<|python_tag|>", "tool_code"].contains { raw.contains($0) }
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// The answer holds the needle (or one of its "a|b" choices), ignoring case and accents, after the clock placeholders.
    static func contains(_ answer: String, _ needle: String) -> Bool {
        let haystack = fold(answer)
        return AppleToolEvalTests.expand(needle).split(separator: "|").contains { haystack.contains(fold(String($0))) }
    }

    static func argumentsOK(_ call: ToolCall) -> Bool {
        guard let arguments = MCPToolHost.arguments(from: call.argumentsJSON) else { return false }
        guard let key = requiredArgument[call.name] else { return true }
        return arguments[key]?.string?.isEmpty == false
    }

    static func score(_ item: AgentToolCase, _ outcome: AgentToolOutcome, includeAnswer: Bool) -> AgentToolScore {
        let calls = outcome.calls
        let toolCorrect = item.expectTool.map { calls.first?.name == $0 } ?? calls.isEmpty
        var argsParsed: Bool?
        if !calls.isEmpty {
            argsParsed = calls.allSatisfy(argumentsOK)
        } else if outcome.unparsedCallText {
            argsParsed = false
        }
        var argsRight: Bool?
        if !item.argsContain.isEmpty {
            let expected = calls.filter { $0.name == item.expectTool }
            argsRight = !expected.isEmpty && expected.allSatisfy { call in
                item.argsContain.allSatisfy { fold(call.argumentsJSON).contains(fold($0)) }
            }
        }
        let answerPassed = outcome.failure == nil && !outcome.answer.isEmpty
            && item.mustContain.allSatisfy { contains(outcome.answer, $0) }
            && item.mustNotContain.allSatisfy { !contains(outcome.answer, $0) }
        return AgentToolScore(
            id: item.id, language: item.language, expectedTool: item.expectTool, chosenTool: calls.first?.name,
            toolCorrect: toolCorrect, argsParsed: argsParsed, argsRight: argsRight, answerPassed: answerPassed,
            wrongToolCalls: calls.filter { $0.name != item.expectTool }.count, calls: calls.count, rounds: outcome.rounds,
            seconds: outcome.seconds, failure: outcome.failure, answer: includeAnswer ? String(outcome.answer.prefix(200)) : nil)
    }

    static func summarize(_ scores: [AgentToolScore], total: Int) -> AgentToolSummary {
        let rounds = scores.compactMap(\.rounds)
        return AgentToolSummary(
            cases: total, ran: scores.count,
            toolCorrect: scores.filter(\.toolCorrect).count,
            withCalls: scores.filter { $0.argsParsed != nil }.count,
            argsParsed: scores.filter { $0.argsParsed == true }.count,
            argsChecked: scores.filter { $0.argsRight != nil }.count,
            argsRight: scores.filter { $0.argsRight == true }.count,
            answerPassed: scores.filter(\.answerPassed).count,
            wrongToolCalls: scores.reduce(0) { $0 + $1.wrongToolCalls },
            roundsCount: rounds.count, roundsTotal: rounds.reduce(0, +), roundsMax: rounds.max() ?? 0,
            failed: scores.filter { $0.failure != nil }.count)
    }

    /// The one-line report the workflow greps into the job summary.
    static func toolLine(_ summary: AgentToolSummary, engine: String) -> String {
        let rounds: String
        if summary.roundsCount == 0 {
            rounds = "n/a"
        } else {
            let average = (Double(summary.roundsTotal) / Double(summary.roundsCount) * 10).rounded() / 10
            rounds = "\(average) avg, \(summary.roundsMax) max"
        }
        var line = "agent eval tools (\(engine)): ran \(summary.ran)/\(summary.cases), tool chosen \(summary.toolCorrect)/\(summary.ran), "
            + "arguments parsed \(summary.argsParsed)/\(summary.withCalls), arguments right \(summary.argsRight)/\(summary.argsChecked), "
            + "answers passed \(summary.answerPassed)/\(summary.ran), wrong tool calls \(summary.wrongToolCalls), rounds \(rounds)"
        if summary.ran < summary.cases { line += ", not run \(summary.cases - summary.ran) (time cap)" }
        if summary.failed > 0 { line += ", stream errors \(summary.failed)" }
        return line
    }
}

// MARK: Running a set

struct AgentToolSection: Codable, Equatable, Sendable {
    var engine: String
    var summary: AgentToolSummary
    var cases: [AgentToolScore]
    /// Times the host asked to approve a call (the model wrote a URL the user did not).
    var approvalsAsked: Int
    var lines: [String]
}

enum AgentToolEvalRunner {
    /// One prompt through `engine` (a `LocalToolEngine` or Apple's engine) with the four tools.
    static func run(
        _ item: AgentToolCase, engine: any ChatEngine, model: ModelDescriptor, rounds: EvalRoundCounter?, approver: EvalApprover
    ) async -> AgentToolOutcome {
        rounds?.reset()
        let host = AgentEvalHost.make(for: item, source: model.source, approver: approver)
        var params = GenerationParams()
        params.temperature = 0
        params.maxTokens = SmokeEnv.maxTokens ?? 1024
        var outcome = AgentToolOutcome()
        var raw = ""
        let clock = ContinuousClock()
        let start = clock.now
        do {
            let messages = [ChatMessage(role: .user, content: item.prompt)]
            for try await delta in engine.stream(model: model, messages: messages, params: params, tools: host) {
                switch delta {
                case .text(let piece): raw += piece
                case .toolCall(let call): outcome.calls.append(call)
                default: break
                }
            }
        } catch {
            outcome.failure = String(describing: error)
        }
        let elapsed = clock.now - start
        outcome.seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        outcome.answer = AgentEvalScoring.answerText(from: raw)
        outcome.unparsedCallText = AgentEvalScoring.hasCallText(raw)
        outcome.rounds = rounds?.count
        return outcome
    }

    /// Every case in order, until the cap. Prints and records the report lines and writes the JSON section.
    static func runSet(
        _ cases: [AgentToolCase], engine: any ChatEngine, model: ModelDescriptor, rounds: EvalRoundCounter?,
        label: String, section: String
    ) async throws -> AgentToolSection {
        let deadline = EvalDeadline(minutes: SmokeEnv.evalMinutes ?? 40)
        let approver = EvalApprover()
        var scores: [AgentToolScore] = []
        for item in cases {
            if deadline.passed() { break }
            let outcome = await run(item, engine: engine, model: model, rounds: rounds, approver: approver)
            scores.append(AgentEvalScoring.score(item, outcome, includeAnswer: !SmokeEnv.external))
        }
        let summary = AgentEvalScoring.summarize(scores, total: cases.count)
        let line = AgentEvalScoring.toolLine(summary, engine: label)
        let result = AgentToolSection(engine: label, summary: summary, cases: scores, approvalsAsked: approver.asked, lines: [line])
        AgentEvalReport.publish(line)
        SmokeReport.record("Agent eval tools (\(label))", String(line.drop { $0 != ":" }.dropFirst(2)))
        try AgentEvalReport.write(section, result)
        return result
    }
}

// MARK: Report

enum AgentEvalReport {
    /// One line to the test log, where the workflow step finds it.
    static func publish(_ line: String) { print(line) }

    /// Adds `section` to the JSON file and keeps the sections other tests wrote. Does nothing without a path.
    static func write<T: Encodable>(_ section: String, _ value: T, to path: String? = SmokeEnv.agentEvalJSON) throws {
        guard let path else { return }
        var root: [String: Any] = [:]
        if let data = FileManager.default.contents(atPath: path),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            root = object
        }
        root[section] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: path))
    }
}
