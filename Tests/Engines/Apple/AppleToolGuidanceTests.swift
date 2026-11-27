import XCTest

@testable import AnyRouter

final class AppleToolGuidanceTests: XCTestCase {
    private func spec(_ name: String) -> ToolSpec {
        ToolSpec(name: name, title: nil, description: "d", inputSchemaJSON: #"{"type":"object","properties":{"q":{"type":"string"}}}"#, isReadOnly: true)
    }

    func testAppleAndLocalModelsBothGetFourTools() {
        XCTAssertEqual(ToolProfile.apple.maxTools, 4)
        XCTAssertEqual(ToolProfile.forModel(.apple), .apple)
        XCTAssertEqual(ToolProfile.forModel(.gguf).maxTools, 4)
    }

    func testTheTimeToolAndTheCalculatorSurviveTheCutInAFullApp() {
        // Built-ins, web search and a long MCP list: the first four must still answer "what time is it".
        let names = ["fetch_url", "current_date_time", "calculator", "read_attachment", "web_search"]
            + (0..<26).map { "firecrawl__tool\($0)" }
        let shaped = ToolProfile.apple.shaped(names.map(spec)).map(\.name)
        XCTAssertEqual(shaped.count, 4)
        XCTAssertTrue(shaped.contains("current_date_time"), "\(shaped)")
        XCTAssertTrue(shaped.contains("calculator"), "\(shaped)")
    }

    func testOnlyTheShapedFourReachTheModel() async {
        let names = ["fetch_url", "current_date_time", "calculator", "read_attachment", "web_search"]
        let specs = ToolProfile.apple.shaped(names.map(spec))
        struct Host: ToolHost {
            let specs: [ToolSpec]
            func execute(_ call: ToolCall) async -> ToolResult { ToolResult(callID: call.id, name: call.name, text: "", isError: false) }
        }
        let tools = AppleDynamicTool.make(specs: specs, host: Host(specs: specs), scope: ToolRunScope(), emit: { _ in })
        XCTAssertEqual(tools.count, 4)
        XCTAssertTrue(tools.contains { $0.name == "current_date_time" })
    }

    func testGuidanceIsAddedOnlyWhenToolsAreOffered() throws {
        XCTAssertEqual(AppleToolGuidance.instructions(base: "Be brief.", offeringTools: false), "Be brief.")
        XCTAssertNil(AppleToolGuidance.instructions(base: nil, offeringTools: false))
        XCTAssertEqual(AppleToolGuidance.instructions(base: nil, offeringTools: true), AppleToolGuidance.text)
        XCTAssertEqual(AppleToolGuidance.instructions(base: "", offeringTools: true), AppleToolGuidance.text)
        let both = try XCTUnwrap(AppleToolGuidance.instructions(base: "Be brief.", offeringTools: true))
        XCTAssertTrue(both.hasPrefix("Be brief.\n\n"))
        XCTAssertTrue(both.hasSuffix(AppleToolGuidance.text))
    }

    func testGuidanceTellsTheModelToUseTheResultAndNotInventPlaces() {
        XCTAssertTrue(AppleToolGuidance.text.contains("exactly the values"))
        XCTAssertTrue(AppleToolGuidance.text.contains("Do not add places"))
        // Every offered tool and these instructions share a 4,096-token window; stay short.
        XCTAssertLessThan(AppleToolGuidance.text.count, 250)
    }

    func testTheRealPromptCarriesTheGuidanceWithTheUsersQuestion() throws {
        let built = try ApplePrompt.build(
            messages: [ChatMessage(role: .user, content: "What time is it?")], params: GenerationParams())
        XCTAssertEqual(built.prompt, "What time is it?")
        XCTAssertEqual(AppleToolGuidance.instructions(base: built.instructions, offeringTools: true), AppleToolGuidance.text)
    }
}
