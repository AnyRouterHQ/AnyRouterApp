import XCTest

@testable import AnyRouter

private struct Echo: BuiltInTool {
    let name: String
    let title = "Echo"
    let summary = "Echoes"
    let description = "Echo the text"
    let inputSchemaJSON = #"{"type":"object","properties":{"text":{"type":"string"}}}"#
    var delay: Double = 0
    var fail: String?

    func run(_ arguments: JSONValue) async throws -> String {
        if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
        if let fail { throw BuiltInToolError(fail) }
        return "echo: " + (arguments["text"]?.string ?? "")
    }
}

private struct NeverAsks: ToolApproving {
    func decide(_ request: ToolApprovalRequest) async -> ToolDecision { .deny }
}

private let searchListing = """
    {"jsonrpc":"2.0","id":0,"result":{"tools":[
      {"name":"firecrawl_search","description":"Search the web","inputSchema":{"type":"object","properties":{"query":{"type":"string"},"limit":{"type":"number"}},"required":["query"]},"annotations":{"readOnlyHint":true}},
      {"name":"get_credits","description":"Balance","inputSchema":{"type":"object"},"annotations":{"readOnlyHint":true}},
      {"name":"calculator","description":"Clashes with the built-in","inputSchema":{"type":"object"},"annotations":{"readOnlyHint":true}}
    ]}}
    """

/// An AnyRouter-like server that has a search tool, served at the real AnyRouter URL.
func serveSearchServer(callBody: @escaping @Sendable (RecordedRequest) -> StubResponse = { MCPFixtures.reply(MCPFixtures.callText, to: $0) }) {
    MCPStubProtocol.register(host: MCPServer.anyRouter.url.host()!) { request in
        switch request.rpcMethod {
        case "tools/list": return MCPFixtures.reply(searchListing, to: request)
        case "tools/call": return callBody(request)
        default: return standardMCPHandler()(request)
        }
    }
}

final class WebSearchBindingTests: XCTestCase {
    private func tool(_ name: String, schema: String, readOnly: Bool = true) throws -> MCPTool {
        let json = #"{"name":"\#(name)","inputSchema":\#(schema),"annotations":{"readOnlyHint":\#(readOnly)}}"#
        return try JSONDecoder().decode(MCPTool.self, from: Data(json.utf8))
    }

    private let trusted = MCPServer.anyRouter
    private let custom = MCPServer(id: "c", name: "C", url: URL(string: "https://example.com/mcp")!, auth: .bearerToken)

    func testFindsTheSearchToolAndItsTextArgument() throws {
        let schema = #"{"type":"object","properties":{"limit":{"type":"number"},"q":{"type":"string"}}}"#
        let match = WebSearchBinding.find(in: [
            (server: trusted, tool: try tool("get_credits", schema: "{}")),
            (server: trusted, tool: try tool("firecrawl_search", schema: schema)),
        ])
        XCTAssertEqual(match?.tool.name, "firecrawl_search")
        XCTAssertEqual(match?.queryKey, "q")
    }

    func testIgnoresCustomServersListToolsAndSchemasWithoutAText() throws {
        let schema = #"{"type":"object","properties":{"query":{"type":"string"}}}"#
        XCTAssertNil(WebSearchBinding.find(in: [(server: custom, tool: try tool("web_search", schema: schema))]))
        XCTAssertNil(WebSearchBinding.find(in: [(server: trusted, tool: try tool("list_search_indexes", schema: schema))]))
        XCTAssertNil(WebSearchBinding.find(in: [(server: trusted, tool: try tool("web_search", schema: #"{"type":"object","properties":{"limit":{"type":"number"}}}"#))]))
        XCTAssertNil(WebSearchBinding.find(in: []))
    }
}

final class AgentToolHostTests: XCTestCase {
    private func call(_ name: String, _ arguments: String = "{}") -> ToolCall {
        ToolCall(id: "c1", name: name, argumentsJSON: arguments)
    }

    private func host(_ tools: [any BuiltInTool], timeout: Double = 5) -> AgentToolHost {
        AgentToolHost(builtIns: tools, search: nil, mcp: nil, builtInTimeout: timeout)
    }

    func testBuiltInsAreListedAsReadOnlySpecsAndRun() async {
        let host = host([Echo(name: "echo")])
        XCTAssertEqual(host.specs.map(\.name), ["echo"])
        XCTAssertEqual(host.specs.map(\.isReadOnly), [true])
        let result = await host.execute(call("echo", #"{"text":"hi"}"#))
        XCTAssertEqual(result, ToolResult(callID: "c1", name: "echo", text: "echo: hi", isError: false))
    }

    func testFailuresBadArgumentsAndUnknownToolsAreErrorResults() async {
        let host = host([Echo(name: "boom", fail: "no luck")])
        let failed = await host.execute(call("boom"))
        XCTAssertEqual(failed.text, "no luck")
        XCTAssertTrue(failed.isError)
        let bad = await host.execute(call("boom", "[1]"))
        XCTAssertEqual(bad.text, "The arguments are not a JSON object.")
        let unknown = await host.execute(call("missing"))
        XCTAssertEqual(unknown.text, "Unknown tool: missing.")
        XCTAssertTrue(unknown.isError)
    }

    func testASlowToolIsStoppedAtItsDeadline() async {
        let host = host([Echo(name: "slow", delay: 30)], timeout: 0.05)
        let result = await host.execute(call("slow"))
        XCTAssertTrue(result.isError)
        XCTAssertEqual(result.text, "The tool took longer than 0.05 seconds and was stopped.")
    }

    func testStoppingTheReplyCancelsARunningTool() async {
        let host = host([Echo(name: "slow", delay: 30)])
        let slow = call("slow")
        let task = Task { await host.execute(slow) }
        try? await Task.sleep(for: .milliseconds(50))
        task.cancel()
        let result = await task.value
        XCTAssertTrue(result.isError)
        XCTAssertEqual(result.text, "The tool call was cancelled.")
    }

    func testLongResultsAreCut() async {
        struct Wall: BuiltInTool {
            let name = "wall", title = "Wall", summary = "", description = "", inputSchemaJSON = "{}"
            func run(_ arguments: JSONValue) async throws -> String { String(repeating: "x", count: 30_000) }
        }
        let result = await host([Wall()]).execute(call("wall"))
        XCTAssertTrue(result.text.hasSuffix("[Result cut at 20000 characters.]"))
    }

    func testReservedNamesPushAnMCPToolBehindItsServerName() throws {
        let server = MCPServer(id: "s", name: "Srv", url: URL(string: "https://example.com/mcp")!, auth: .none)
        let reserved = AgentToolHost.reservedNames(builtIns: [CalculatorTool()], hasSearch: true)
        XCTAssertEqual(reserved, ["calculator", "web_search"])
        let names = MCPToolHost.uniqueNames(
            for: [(server: server, tool: MCPTool(name: "calculator")), (server: server, tool: MCPTool(name: "other"))],
            reserved: reserved)
        XCTAssertEqual(names, ["Srv__calculator", "other"])
    }
}

@MainActor
final class ToolRegistryTests: XCTestCase {
    private let token = "tok"

    private func makeRegistry(
        defaults: UserDefaults? = nil, builtIns: [any BuiltInTool] = ToolRegistry.standardBuiltIns()
    ) -> ToolRegistry {
        let defaults = defaults ?? testDefaults()
        let integrations = IntegrationsStore(
            defaults: defaults, credentials: FakeCredentialStore(),
            anyRouterToken: { "tok" }, session: MCPStubProtocol.session())
        return ToolRegistry(integrations: integrations, builtIns: builtIns, defaults: defaults)
    }

    func testBuiltInsAreOnByDefaultAndTheirSwitchesPersist() {
        let defaults = testDefaults()
        let registry = makeRegistry(defaults: defaults)
        XCTAssertEqual(registry.tools.map(\.name), ["fetch_url", "current_date_time", "calculator"])
        XCTAssertTrue(registry.tools.allSatisfy { $0.enabled && $0.source == .builtIn && !$0.needsApproval })

        registry.setBuiltIn("calculator", enabled: false)
        XCTAssertFalse(registry.tools.first { $0.name == "calculator" }!.enabled)
        let reopened = makeRegistry(defaults: defaults)
        XCTAssertFalse(reopened.isBuiltInEnabled("calculator"))
        reopened.setBuiltIn("calculator", enabled: true)
        XCTAssertTrue(makeRegistry(defaults: defaults).isBuiltInEnabled("calculator"))
    }

    func testHostHasOnlyTheEnabledToolsAndIsNilWhenNothingIsOn() {
        let registry = makeRegistry()
        XCTAssertEqual(registry.makeHost(approver: NeverAsks())?.specs.map(\.name), ["fetch_url", "current_date_time", "calculator"])
        for tool in ["fetch_url", "current_date_time", "calculator"] { registry.setBuiltIn(tool, enabled: false) }
        XCTAssertNil(registry.makeHost(approver: NeverAsks()))
    }

    func testReadAttachmentExistsOnlyWithAnAttachmentProvider() async {
        struct Files: AttachmentTextProviding {
            func attachmentNames() async -> [String] { ["notes.txt"] }
            func text(named name: String) async -> String? { name == "notes.txt" ? "remember the milk" : nil }
        }
        let registry = makeRegistry()
        XCTAssertFalse(registry.tools.contains { $0.name == "read_attachment" })
        registry.attachments = Files()
        XCTAssertTrue(registry.tools.contains { $0.name == "read_attachment" })
        let host = try? XCTUnwrap(registry.makeHost(approver: NeverAsks()))
        let listed = await host?.execute(ToolCall(id: "1", name: "read_attachment", argumentsJSON: "{}"))
        XCTAssertEqual(listed?.text, "Attachments: notes.txt")
        let read = await host?.execute(ToolCall(id: "2", name: "read_attachment", argumentsJSON: #"{"name":"notes.txt"}"#))
        XCTAssertEqual(read?.text, "remember the milk")
        let missing = await host?.execute(ToolCall(id: "3", name: "read_attachment", argumentsJSON: #"{"name":"x"}"#))
        XCTAssertEqual(missing?.isError, true)
    }

    func testAnyRouterToolsMergeAndWebSearchForwardsToTheSearchTool() async throws {
        let seen = Seen()
        serveSearchServer { request in
            seen.add(request)
            return MCPFixtures.reply(MCPFixtures.callText, to: request)
        }
        let registry = makeRegistry()
        XCTAssertNil(registry.searchMatch, "no web_search before the AnyRouter server is connected")
        await registry.integrations.refresh(.anyRouter)

        let names = registry.tools.map(\.name)
        XCTAssertEqual(names, [
            "web_search", "fetch_url", "current_date_time", "calculator",
            "firecrawl_search", "get_credits", "calculator",
        ])
        let mcpCalculator = registry.tools.last!
        XCTAssertEqual(mcpCalculator.source, .mcp(serverID: "anyrouter", serverName: "AnyRouter"))
        XCTAssertFalse(mcpCalculator.needsApproval, "the app's own server is trusted for read-only tools")

        let host = try XCTUnwrap(registry.makeHost(approver: NeverAsks()))
        // web_search replaces firecrawl_search; the MCP calculator gives way to the built-in one.
        XCTAssertEqual(host.specs.map(\.name), [
            "fetch_url", "current_date_time", "calculator", "web_search", "get_credits", "AnyRouter__calculator",
        ])
        let result = await host.execute(ToolCall(id: "s", name: "web_search", argumentsJSON: #"{"query":"swift concurrency"}"#))
        XCTAssertFalse(result.isError)
        let sent = try XCTUnwrap(seen.last)
        XCTAssertEqual(sent.body?["params"]?["name"]?.string, "firecrawl_search")
        XCTAssertEqual(sent.body?["params"]?["arguments"], .object(["query": .string("swift concurrency")]))

        let empty = await host.execute(ToolCall(id: "e", name: "web_search", argumentsJSON: "{}"))
        XCTAssertEqual(empty.text, "Missing the \"query\" argument.")

        // Turning the search off hides web_search but leaves the MCP tool behind it available.
        registry.setBuiltIn("web_search", enabled: false)
        let withoutSearch = try XCTUnwrap(registry.makeHost(approver: NeverAsks()))
        XCTAssertFalse(withoutSearch.specs.contains { $0.name == "web_search" })
        XCTAssertTrue(withoutSearch.specs.contains { $0.name == "firecrawl_search" })
    }

    func testMCPSwitchesStayWithTheIntegrationsStore() async throws {
        serveSearchServer()
        let registry = makeRegistry()
        await registry.integrations.refresh(.anyRouter)
        let credits = try XCTUnwrap(registry.integrations.state(for: .anyRouter).tools.first { $0.name == "get_credits" })
        registry.integrations.setEnabled(false, tool: credits, on: .anyRouter)
        XCTAssertFalse(registry.tools.first { $0.name == "get_credits" }!.enabled)
        XCTAssertFalse(try XCTUnwrap(registry.makeHost(approver: NeverAsks())).specs.contains { $0.name == "get_credits" })
    }

    func testSignOutRemovesTheAnyRouterToolsFromTheList() async {
        serveSearchServer()
        let registry = makeRegistry()
        await registry.integrations.refresh(.anyRouter)
        XCTAssertTrue(registry.tools.contains { $0.name == "get_credits" })
        registry.integrations.accountChanged(signedIn: false)
        XCTAssertEqual(registry.tools.map(\.name), ["fetch_url", "current_date_time", "calculator"])
    }
}

/// Records tool-call requests.
private final class Seen: @unchecked Sendable {
    private let lock = NSLock()
    private var all: [RecordedRequest] = []
    func add(_ request: RecordedRequest) { lock.withLock { all.append(request) } }
    var last: RecordedRequest? { lock.withLock { all.last } }
}
