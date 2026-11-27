import Foundation
import Testing
import XCTest

@testable import AnyRouter

struct ToolProfileTests {
    private func spec(_ name: String, _ description: String = "d") -> ToolSpec {
        ToolSpec(name: name, title: nil, description: description, inputSchemaJSON: "{}", isReadOnly: true)
    }

    @Test func cloudModelsGetEveryToolUntouched() {
        let specs = (0..<20).map { spec("t\($0)", String(repeating: "word ", count: 100)) }
        #expect(ToolProfile.full.shaped(specs) == specs)
    }

    @Test func smallModelsGetFourToolsAndTheClockThenTheCalculatorThenSearchComeFirst() {
        let filler = (0..<9).map { spec("other\($0)") }
        let specs = filler + [spec("calculator"), spec("web_fetch_exa"), spec("web_search_exa")]
        let shaped = ToolProfile.compact.shaped(specs)
        #expect(shaped.count == 4)
        #expect(shaped.map(\.name).prefix(3) == ["calculator", "web_search_exa", "web_fetch_exa"])
        #expect(shaped.map(\.name).dropFirst(3) == ["other0"])
    }

    /// The one cap on Apple's four-tool window: the clock, the calculator, search and one page reader.
    @Test func appleKeepsTheClockTheCalculatorSearchAndOnePageReader() {
        let names = ["fetch_url", "current_date_time", "calculator", "read_attachment", "web_search_exa", "web_fetch_exa"]
        #expect(ToolProfile.apple.shaped(names.map { spec($0) }).map(\.name) == [
            "current_date_time", "calculator", "web_search_exa", "fetch_url",
        ])
        let signedIn = ["fetch_url", "current_date_time", "calculator", "read_attachment", "web_search"]
            + (0..<26).map { "firecrawl__tool\($0)" }
        #expect(ToolProfile.apple.shaped(signedIn.map { spec($0) }).map(\.name) == [
            "current_date_time", "calculator", "web_search", "fetch_url",
        ])
    }

    @Test func localModelsAndAppleBothKeepFour() {
        #expect(ToolProfile.apple.maxTools == 4)
        #expect(ToolProfile.compact.maxTools == 4)
        #expect(ToolProfile.apple.maxResultCharacters == ToolProfile.compact.maxResultCharacters)
    }

    @Test func smallModelsKeepTheGivenOrderWhenNothingIsDropped() {
        let specs = [spec("web_search_exa"), spec("calculator"), spec("a"), spec("fetch_url")]
        #expect(ToolProfile.compact.shaped(specs).map(\.name) == ["web_search_exa", "calculator", "a", "fetch_url"])
    }

    @Test func smallModelsGetShortDescriptions() {
        let long = "Search the web for any topic. " + String(repeating: "More detail follows here. ", count: 40)
        let shaped = ToolProfile.compact.shaped([spec("web_search_exa", long)])
        // Cut after the last whole sentence that fits.
        #expect(shaped[0].description.count <= 160)
        #expect(shaped[0].description.hasPrefix("Search the web for any topic. More detail"))
        #expect(shaped[0].description.hasSuffix("here."))
        #expect(ToolProfile.shortened("a  b\n c", limit: 160) == "a b c")
        #expect(ToolProfile.shortened("alpha beta gamma delta epsilon zeta eta theta", limit: 20) == "alpha beta gamma…")
        #expect(ToolProfile.shortened("Hi. then a long run of words without any end marks at all here", limit: 30) == "Hi. then a long run of words…")
        #expect(ToolProfile.shortened("abcdefghijklmnopqrstuvwxyz", limit: 10) == "abcdefghij…")
    }

    @Test func modelSourceChoosesTheProfile() {
        #expect(ToolProfile.forModel(.apple) == .apple)
        #expect(ToolProfile.forModel(.gguf) == .compact)
        #expect(ToolProfile.forModel(.mlx) == .compact)
        #expect(ToolProfile.forModel(.anyrouter) == .full)
        #expect(ToolProfile.forModel(nil) == .full)
    }

    @Test func resultsAreCutAtTheProfileLimit() {
        let cut = ToolProfile.compact.clipped(String(repeating: "x", count: 7_000))
        #expect(cut.hasSuffix("[Result cut at 6000 characters.]"))
        #expect(ToolProfile.compact.clipped("short") == "short")
    }
}

private struct Wall: BuiltInTool {
    let name = "wall", title = "Wall", summary = "", description = "", inputSchemaJSON = "{}"
    func run(_ arguments: JSONValue) async throws -> String { String(repeating: "x", count: 30_000) }
}

private struct Quiet: BuiltInTool {
    let name: String
    let title = "Quiet", summary = "", description = "", inputSchemaJSON = "{}"
    func run(_ arguments: JSONValue) async throws -> String { "ran" }
}

private final class DenyingApprover: ToolApproving, @unchecked Sendable {
    private let lock = NSLock()
    private var asked: [ToolApprovalRequest] = []
    var requests: [ToolApprovalRequest] { lock.withLock { asked } }
    func decide(_ request: ToolApprovalRequest) async -> ToolDecision {
        lock.withLock { asked.append(request) }
        return .deny
    }
}

final class ToolProfileHostTests: XCTestCase {
    private func call(_ name: String, _ arguments: String = "{}") -> ToolCall {
        ToolCall(id: "1", name: name, argumentsJSON: arguments)
    }

    func testASmallModelsAnswerIsCutBeforeItGoesBackIntoTheChat() async {
        let host = AgentToolHost(builtIns: [Wall()], search: nil, mcp: nil, profile: .compact)
        let result = await host.execute(call("wall"))
        XCTAssertTrue(result.text.hasPrefix("xxx"))
        XCTAssertTrue(result.text.hasSuffix("\n[Result cut at 6000 characters.]"))
        XCTAssertEqual(result.text.count, 6_000 + "\n[Result cut at 6000 characters.]".count)
    }

    func testACloudModelKeepsTheTwentyThousandCharacterCap() async {
        let host = AgentToolHost(builtIns: [Wall()], search: nil, mcp: nil)
        let result = await host.execute(call("wall"))
        XCTAssertTrue(result.text.hasSuffix("\n[Result cut at 20000 characters.]"))
        XCTAssertEqual(result.text.count, 20_000 + "\n[Result cut at 20000 characters.]".count)
    }

    /// The model only sees eight tools, but a call to one it was not shown still gets the address check.
    func testAToolLeftOutOfTheListStillMeetsTheAddressCheck() async {
        let tools = (0..<9).map { Quiet(name: "tool\($0)") }
        let approver = DenyingApprover()
        let host = AgentToolHost(builtIns: tools, search: nil, mcp: nil, approver: approver, profile: .compact)
        XCTAssertEqual(host.specs.count, 8)
        XCTAssertFalse(host.specs.contains { $0.name == "tool8" })
        let result = await host.execute(call("tool8", #"{"url":"https://unwritten.example/page"}"#))
        XCTAssertTrue(result.isError)
        XCTAssertEqual(approver.requests.count, 1)
        XCTAssertEqual(approver.requests.first?.urls, ["https://unwritten.example/page"])
    }
}
