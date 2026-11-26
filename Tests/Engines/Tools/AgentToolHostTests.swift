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
        XCTAssertEqual(registry.tools.map(\.name), ["fetch_url", "current_date_time", "calculator", "read_attachment"])
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

    func testReadAttachmentIsOfferedOnlyInAChatWithAttachments() async {
        func attachment(_ name: String, text: String?) -> Attachment {
            Attachment(id: UUID(), kind: .text, filename: name, utType: "public.plain-text", byteCount: 10,
                       relativePath: "t/\(name)", extractedText: text)
        }
        let registry = makeRegistry()
        XCTAssertTrue(registry.tools.contains { $0.name == "read_attachment" }, "listed in Settings always")
        XCTAssertFalse(registry.makeHost(approver: NeverAsks())!.specs.contains { $0.name == "read_attachment" })

        let files = [attachment("notes.txt", text: "remember the milk"), attachment("scan.png", text: nil)]
        let host = registry.makeHost(approver: NeverAsks(), attachments: files)!
        XCTAssertTrue(host.specs.contains { $0.name == "read_attachment" })
        let listed = await host.execute(ToolCall(id: "1", name: "read_attachment", argumentsJSON: "{}"))
        XCTAssertEqual(listed.text, "Attachments: notes.txt, scan.png")
        let read = await host.execute(ToolCall(id: "2", name: "read_attachment", argumentsJSON: #"{"name":"NOTES.txt"}"#))
        XCTAssertEqual(read.text, "remember the milk")
        let blank = await host.execute(ToolCall(id: "3", name: "read_attachment", argumentsJSON: #"{"name":"scan.png"}"#))
        XCTAssertEqual(blank.text, "This attachment has no readable text (text).")
        let missing = await host.execute(ToolCall(id: "4", name: "read_attachment", argumentsJSON: #"{"name":"x"}"#))
        XCTAssertTrue(missing.isError)

        registry.setBuiltIn("read_attachment", enabled: false)
        XCTAssertFalse(registry.makeHost(approver: NeverAsks(), attachments: files)!.specs.contains { $0.name == "read_attachment" })
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
            "web_search", "fetch_url", "current_date_time", "calculator", "read_attachment",
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
        XCTAssertEqual(registry.tools.map(\.name), ["fetch_url", "current_date_time", "calculator", "read_attachment"])
    }
}

/// Records tool-call requests.
private final class Seen: @unchecked Sendable {
    private let lock = NSLock()
    private var all: [RecordedRequest] = []
    func add(_ request: RecordedRequest) { lock.withLock { all.append(request) } }
    var last: RecordedRequest? { lock.withLock { all.last } }
}

/// The real AnyRouter tool list, end to end through the registry.
@MainActor
final class AnyRouterRealToolsTests: XCTestCase {
    private func tools() throws -> [MCPTool] {
        let json = try XCTUnwrap(JSONValue.parse(MCPFixtures.anyRouterToolsList))
        return try XCTUnwrap(json["result"]?["tools"]?.array).map { try $0.decode(MCPTool.self) }
    }

    private let expectedReadOnly: Set<String> = [
        "list_models", "recommend_model", "list_okf_concepts", "get_okf_concept", "get_system_status",
        "firecrawl__firecrawl_search", "firecrawl__firecrawl_scrape", "firecrawl__firecrawl_map",
        "firecrawl__firecrawl_check_crawl_status", "firecrawl__firecrawl_agent_status",
        "firecrawl__firecrawl_monitor_check", "firecrawl__firecrawl_monitor_checks",
        "firecrawl__firecrawl_monitor_get", "firecrawl__firecrawl_monitor_list",
        "firecrawl__firecrawl_research_inspect_paper", "firecrawl__firecrawl_research_read_paper",
        "firecrawl__firecrawl_research_related_papers", "firecrawl__firecrawl_research_search_github",
        "firecrawl__firecrawl_research_search_papers",
    ]

    func testTheListDecodesAndOnlyReadingToolsAreReadOnly() throws {
        let all = try tools()
        XCTAssertEqual(all.count, 31)
        XCTAssertEqual(all.filter { $0.name.hasPrefix("firecrawl__") }.count, 26)
        let readOnly = Set(all.filter { AnyRouterToolPolicy.isReadOnly($0) }.map(\.name))
        XCTAssertEqual(readOnly, expectedReadOnly)
        for name in ["monitor_create", "monitor_update", "monitor_delete", "monitor_run", "interact", "interact_stop",
                     "crawl", "extract", "agent", "parse", "feedback", "search_feedback"] {
            let tool = try XCTUnwrap(all.first { $0.name == "firecrawl__firecrawl_" + name }, name)
            XCTAssertFalse(MCPServer.anyRouter.skipsApproval(tool), name)
            XCTAssertFalse(MCPServer.anyRouter.enabledByDefault(tool), name)
        }
        // A custom server gets none of this: its hints never waive approval, and its tools start on.
        let custom = MCPServer(id: "c", name: "C", url: URL(string: "https://example.com/mcp")!, auth: .bearerToken)
        let search = try XCTUnwrap(all.first { $0.name == "firecrawl__firecrawl_search" })
        XCTAssertFalse(custom.skipsApproval(search))
        XCTAssertTrue(custom.enabledByDefault(search))
    }

    func testToolNamesFitModelAPIsAndStayUnique() throws {
        let server = MCPServer.anyRouter
        let names = MCPToolHost.uniqueNames(for: try tools().map { (server: server, tool: $0) })
        XCTAssertEqual(Set(names).count, 31)
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
        for name in names {
            XCTAssertLessThanOrEqual(name.count, 64, name)
            XCTAssertTrue(name.unicodeScalars.allSatisfy(allowed.contains), name)
        }
    }

    func testSearchAndScrapeBindToTheFirecrawlTools() throws {
        let enabled = try tools().map { (server: MCPServer.anyRouter, tool: $0) }
        let search = try XCTUnwrap(WebSearchBinding.find(in: enabled))
        XCTAssertEqual(search.tool.name, "firecrawl__firecrawl_search")
        XCTAssertEqual(search.queryKey, "query")
        let scrape = try XCTUnwrap(WebSearchBinding.findScrape(in: enabled))
        XCTAssertEqual(scrape.tool.name, "firecrawl__firecrawl_scrape")
        XCTAssertEqual(scrape.queryKey, "url")
        XCTAssertEqual(scrape.extra, ["onlyMainContent": .bool(true)])
    }

    // MARK: Through the registry

    private func serve(call: @escaping @Sendable (RecordedRequest) -> StubResponse) {
        MCPStubProtocol.register(host: MCPServer.anyRouter.url.host()!) { request in
            switch request.rpcMethod {
            case "tools/list": return MCPFixtures.reply(MCPFixtures.anyRouterToolsList, to: request)
            case "tools/call": return call(request)
            default: return standardMCPHandler()(request)
            }
        }
    }

    private func registry() -> ToolRegistry {
        let defaults = testDefaults()
        let store = IntegrationsStore(
            defaults: defaults, credentials: FakeCredentialStore(),
            anyRouterToken: { "tok" }, session: MCPStubProtocol.session())
        return ToolRegistry(integrations: store, builtIns: [Echo(name: "fetch_url")], defaults: defaults)
    }

    func testDefaultsOfferOnlyReadingToolsAndShowSearchAndScrapeAsBuiltIns() async throws {
        serve { MCPFixtures.reply(MCPFixtures.callText, to: $0) }
        let registry = registry()
        await registry.integrations.refresh(.anyRouter)

        let listed = registry.tools.filter { $0.source != .builtIn }
        XCTAssertEqual(listed.count, 31)
        XCTAssertEqual(Set(listed.filter(\.enabled).map(\.name)), expectedReadOnly)
        XCTAssertEqual(listed.filter(\.needsApproval).count, 12)

        let specs = Set(try XCTUnwrap(registry.makeHost(approver: NeverAsks())).specs.map(\.name))
        XCTAssertTrue(specs.contains("web_search"))
        XCTAssertTrue(specs.contains("fetch_url"))
        // The tools behind them are not offered twice, and tools that act are off until the user turns them on.
        XCTAssertFalse(specs.contains("firecrawl__firecrawl_search"))
        XCTAssertFalse(specs.contains("firecrawl__firecrawl_scrape"))
        XCTAssertFalse(specs.contains("firecrawl__firecrawl_monitor_create"))
        XCTAssertTrue(specs.contains("firecrawl__firecrawl_map"))
        XCTAssertEqual(specs.count, 1 + 1 + 17, "fetch_url, web_search, then 17 more reading tools")
    }

    func testAToolThatActsNeedsApprovalEvenAfterTheUserTurnsItOn() async throws {
        let seen = SeenCalls()
        serve { seen.add($0); return MCPFixtures.reply(MCPFixtures.callText, to: $0) }
        let registry = registry()
        await registry.integrations.refresh(.anyRouter)
        let create = try XCTUnwrap(registry.integrations.state(for: .anyRouter).tools.first { $0.name == "firecrawl__firecrawl_monitor_create" })
        registry.integrations.setEnabled(true, tool: create, on: .anyRouter)
        XCTAssertTrue(registry.integrations.isEnabled(create, on: .anyRouter))

        let host = try XCTUnwrap(registry.makeHost(approver: NeverAsks()))
        XCTAssertTrue(host.specs.contains { $0.name == "firecrawl__firecrawl_monitor_create" })
        let result = await host.execute(ToolCall(id: "m", name: "firecrawl__firecrawl_monitor_create", argumentsJSON: "{}"))
        XCTAssertTrue(result.isError)
        XCTAssertEqual(result.text, "The user did not allow this tool call.")
        XCTAssertNil(seen.last, "a denied call never reaches the server")

        // Turning it back off returns to the stored default, so nothing is left behind.
        registry.integrations.setEnabled(false, tool: create, on: .anyRouter)
        XCTAssertTrue(registry.integrations.overrides.isEmpty)
    }

    func testFetchUrlPrefersTheScrapeToolAndFallsBackToTheDevice() async throws {
        let seen = SeenCalls()
        let failing = Flag()
        serve { request in
            seen.add(request)
            return failing.value
                ? MCPFixtures.reply(MCPFixtures.callError, to: request)
                : MCPFixtures.reply(##"{"jsonrpc":"2.0","id":0,"result":{"content":[{"type":"text","text":"# Page\nHello"}]}}"##, to: request)
        }
        let registry = registry()
        await registry.integrations.refresh(.anyRouter)
        let host = try XCTUnwrap(registry.makeHost(approver: NeverAsks()))
        let call = ToolCall(id: "f", name: "fetch_url", argumentsJSON: #"{"url":"https://example.com/a"}"#)

        let scraped = await host.execute(call)
        XCTAssertEqual(scraped.text, "# Page\nHello")
        let sent = try XCTUnwrap(seen.last)
        XCTAssertEqual(sent.body?["params"]?["name"]?.string, "firecrawl__firecrawl_scrape")
        XCTAssertEqual(sent.body?["params"]?["arguments"]?["url"]?.string, "https://example.com/a")
        XCTAssertEqual(sent.body?["params"]?["arguments"]?["onlyMainContent"]?.bool, true)

        failing.value = true
        let fallback = await host.execute(call)
        XCTAssertFalse(fallback.isError)
        XCTAssertTrue(fallback.text.hasPrefix("echo:"), "the on-device fetch answered")

        // With fetch_url switched off the scrape tool is an ordinary tool again.
        registry.setBuiltIn("fetch_url", enabled: false)
        let specs = Set(try XCTUnwrap(registry.makeHost(approver: NeverAsks())).specs.map(\.name))
        XCTAssertFalse(specs.contains("fetch_url"))
        XCTAssertTrue(specs.contains("firecrawl__firecrawl_scrape"))
    }
}

private final class SeenCalls: @unchecked Sendable {
    private let lock = NSLock()
    private var all: [RecordedRequest] = []
    func add(_ request: RecordedRequest) { lock.withLock { all.append(request) } }
    var last: RecordedRequest? { lock.withLock { all.last } }
}
