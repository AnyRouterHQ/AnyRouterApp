import XCTest

@testable import AnyRouter

private final class EvalFixtureAnchor {}

/// Prompts a person can run on a device to see whether the on-device model uses the built-in tools well. The model run is
/// opt-in (`RUN_DEVICE_EVALS=1`) and skips everywhere else with a message that says so; the fixture checks always run.
/// Cases live in `Fixtures/apple-tool-evals.json`.
final class AppleToolEvalTests: XCTestCase {
    struct Case: Decodable {
        var id: String
        var prompt: String
        var expectTool: String?
        var mustContain: [String]
        var mustNotContain: [String]
    }

    struct File: Decodable {
        var cases: [Case]
    }

    private func loadCases() throws -> [Case] {
        let url = try XCTUnwrap(Bundle(for: EvalFixtureAnchor.self).url(forResource: "apple-tool-evals", withExtension: "json"))
        return try JSONDecoder().decode(File.self, from: Data(contentsOf: url)).cases
    }

    /// `{year}`, `{month}` and `{weekday}` become what the clock shows now.
    static func expand(_ text: String, now: Date = Date(), zone: TimeZone = .current) -> String {
        func formatted(_ pattern: String) -> String {
            let format = DateFormatter()
            format.locale = Locale(identifier: "en_US_POSIX")
            format.timeZone = zone
            format.dateFormat = pattern
            return format.string(from: now)
        }
        return text.replacingOccurrences(of: "{year}", with: formatted("yyyy"))
            .replacingOccurrences(of: "{month}", with: formatted("MMMM"))
            .replacingOccurrences(of: "{weekday}", with: formatted("EEEE"))
    }

    // MARK: The fixture itself runs everywhere

    func testTheEvalListIsWellFormed() throws {
        let cases = try loadCases()
        XCTAssertGreaterThanOrEqual(cases.count, 6)
        XCTAssertEqual(Set(cases.map(\.id)).count, cases.count, "ids are unique")
        let known: Set<String> = ["current_date_time", "calculator"]
        for item in cases {
            XCTAssertFalse(item.prompt.isEmpty, item.id)
            if let tool = item.expectTool { XCTAssertTrue(known.contains(tool), "\(item.id) names an unknown tool") }
        }
        XCTAssertTrue(cases.contains { $0.expectTool == nil }, "keeps a control prompt that needs no tool")
    }

    func testPlaceholdersAreFilledFromTheClock() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)  // Friday 15 January 2027
        XCTAssertEqual(Self.expand("{weekday} {month} {year}", now: date, zone: TimeZone(identifier: "GMT")!), "Friday January 2027")
        XCTAssertEqual(Self.expand("no placeholders"), "no placeholders")
    }

    // MARK: On a device

    /// Opt in with `RUN_DEVICE_EVALS=1` in the test process (for `xcodebuild`: `TEST_RUNNER_RUN_DEVICE_EVALS=1`, or the scheme's
    /// environment variables in Xcode). The model can report itself available on a CI host and still not answer like it does on a
    /// phone, so availability alone never starts the evals.
    func testOnDeviceModelUsesTheToolsAndAnswersFromThem() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["RUN_DEVICE_EVALS"] == "1",
            "On-device evals are opt-in: set RUN_DEVICE_EVALS=1 and run on a device with Apple Intelligence.")
        if let note = AppleFoundationEngine.unavailabilityNote() {
            throw XCTSkip("Apple Foundation Models is unavailable on this host (\(note)). Run the evals on a device with Apple Intelligence.")
        }
        let engine = AppleFoundationEngine()
        let available = try await engine.availableModels()
        let model = try XCTUnwrap(available.first)
        let host = AgentToolHost(builtIns: [CurrentDateTimeTool(), CalculatorTool()], search: nil, mcp: nil)
        var failures: [String] = []
        for item in try loadCases() {
            var text = ""
            var called: [String] = []
            do {
                for try await delta in engine.stream(
                    model: model, messages: [ChatMessage(role: .user, content: item.prompt)],
                    params: GenerationParams(), tools: host) {
                    switch delta {
                    case .text(let piece): text += piece
                    case .toolCall(let call): called.append(call.name)
                    default: break
                    }
                }
            } catch {
                failures.append("\(item.id): the stream failed: \(error.localizedDescription)")
                continue
            }
            let lower = text.lowercased()
            if let tool = item.expectTool, !called.contains(tool) { failures.append("\(item.id): did not call \(tool); called \(called)") }
            if item.expectTool == nil, !called.isEmpty { failures.append("\(item.id): called \(called) for a plain question") }
            for needle in item.mustContain where !lower.contains(Self.expand(needle).lowercased()) {
                failures.append("\(item.id): the answer lacks \"\(Self.expand(needle))\": \(text)")
            }
            for needle in item.mustNotContain where lower.contains(needle.lowercased()) {
                failures.append("\(item.id): the answer mentions \"\(needle)\": \(text)")
            }
        }
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n"))
    }
}
