import XCTest

@testable import AnyRouter

/// Opt-in: talks to the real AnyRouter MCP server.
/// Run with `ANYROUTER_E2E_API_KEY` set (an LLM key reaches `list_models` and `recommend_model`;
/// a sign-in token reaches the full set). Skipped otherwise, so CI stays offline.
final class MCPLiveTests: XCTestCase {
    func testAnyRouterServerListsAndCallsTools() async throws {
        let key = ProcessInfo.processInfo.environment["ANYROUTER_E2E_API_KEY"] ?? ""
        try XCTSkipUnless(!key.isEmpty, "ANYROUTER_E2E_API_KEY is not set")
        let client = MCPClient(server: .anyRouter, token: { key })

        let info = try await client.connect()
        XCTAssertFalse(info.protocolVersion.isEmpty)

        let tools = try await client.listTools()
        XCTAssertFalse(tools.isEmpty)
        // Log names only, never values from the account.
        print("MCP live tools:", tools.map(\.name).joined(separator: ", "))
        XCTAssertTrue(tools.contains { $0.name == "list_models" })

        let result = try await client.callTool(name: "list_models", arguments: .object(["limit": .number(1)]))
        XCTAssertFalse(result.isError, result.text)
        XCTAssertFalse(result.text.isEmpty)
        await client.close()
    }
}
