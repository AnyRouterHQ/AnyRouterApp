import XCTest

@testable import AnyRouter

private final class ScriptedApprover: ToolApproving, @unchecked Sendable {
    private let lock = NSLock()
    private var asked: [ToolApprovalRequest] = []
    private let decision: ToolDecision

    init(_ decision: ToolDecision) { self.decision = decision }

    var requests: [ToolApprovalRequest] { lock.withLock { asked } }

    func decide(_ request: ToolApprovalRequest) async -> ToolDecision {
        lock.withLock { asked.append(request) }
        return decision
    }
}

final class MCPToolHostTests: XCTestCase {
    private func server(_ name: String, _ url: URL, auth: MCPServer.Auth = .none) -> MCPServer {
        MCPServer(id: name.lowercased(), name: name, url: url, auth: auth)
    }

    private func makeHost(
        approver: ScriptedApprover = ScriptedApprover(.allowOnce),
        permissions: ToolPermissionStore? = nil,
        auth: MCPServer.Auth = .none,
        handler: @escaping @Sendable (RecordedRequest) -> StubResponse = standardMCPHandler()
    ) -> (host: MCPToolHost, url: URL, approver: ScriptedApprover, permissions: ToolPermissionStore) {
        let url = MCPStubProtocol.register(handler)
        let srv = server("Alpha", url, auth: auth)
        let session = MCPStubProtocol.session()
        let permissions = permissions ?? ToolPermissionStore(defaults: testDefaults())
        let tools = [
            MCPTool(name: "get_credits", description: "Balance", annotations: .init(readOnlyHint: true)),
            MCPTool(name: "create_key", title: "Create key", description: "Make a key"),
        ]
        let host = MCPToolHost(
            enabled: tools.map { (server: srv, tool: $0) },
            client: { MCPClient(server: $0, token: { nil }, session: session) },
            approver: approver,
            permissions: permissions
        )
        return (host, url, approver, permissions)
    }

    private func call(_ name: String, _ arguments: String = "{}") -> ToolCall {
        ToolCall(id: "call_1", name: name, argumentsJSON: arguments)
    }

    func testSpecsCarrySchemaReadOnlyFlagAndTitle() {
        let specs = makeHost(auth: .anyRouterSignIn).host.specs
        XCTAssertEqual(specs.map(\.name), ["get_credits", "create_key"])
        XCTAssertEqual(specs.map(\.isReadOnly), [true, false])
        XCTAssertEqual(specs[1].title, "Create key")
        XCTAssertEqual(specs[0].inputSchemaJSON, #"{"type":"object"}"#)
    }

    func testACustomServerCannotWaiveApprovalWithAReadOnlyHint() async {
        let made = makeHost(approver: ScriptedApprover(.deny))
        XCTAssertEqual(made.host.specs.map(\.isReadOnly), [false, false])
        let result = await made.host.execute(call("get_credits"))
        XCTAssertTrue(result.isError)
        XCTAssertEqual(made.approver.requests.map(\.spec.name), ["get_credits"])
        XCTAssertFalse(MCPStubProtocol.requests(for: made.url).contains { $0.rpcMethod == "tools/call" })
    }

    func testOnlyTheUsersAlwaysAllowLetsACustomServersToolSkipApproval() async {
        let permissions = ToolPermissionStore(defaults: testDefaults())
        permissions.allow(serverID: "alpha", toolName: "get_credits")
        let made = makeHost(approver: ScriptedApprover(.deny), permissions: permissions)
        let result = await made.host.execute(call("get_credits"))
        XCTAssertFalse(result.isError)
        XCTAssertTrue(made.approver.requests.isEmpty)
    }

    func testReadOnlyToolRunsWithoutAskingAndSendsArguments() async throws {
        let made = makeHost(auth: .anyRouterSignIn)
        let result = await made.host.execute(call("get_credits", #"{"days":3}"#))
        XCTAssertFalse(result.isError)
        XCTAssertEqual(result.callID, "call_1")
        XCTAssertEqual(result.name, "get_credits")
        XCTAssertTrue(made.approver.requests.isEmpty)
        let sent = try XCTUnwrap(MCPStubProtocol.requests(for: made.url).last)
        XCTAssertEqual(sent.body?["params"]?["name"]?.string, "get_credits")
        XCTAssertEqual(sent.body?["params"]?["arguments"]?["days"]?.number, 3)
    }

    func testToolNotMarkedReadOnlyAsksFirstAndAllowOnceDoesNotStick() async {
        let made = makeHost(approver: ScriptedApprover(.allowOnce))
        let first = await made.host.execute(call("create_key"))
        XCTAssertFalse(first.isError)
        _ = await made.host.execute(call("create_key"))
        XCTAssertEqual(made.approver.requests.count, 2)
        XCTAssertEqual(made.approver.requests.first?.serverName, "Alpha")
        XCTAssertEqual(made.approver.requests.first?.spec.name, "create_key")
    }

    func testDenyStopsTheCallBeforeItReachesTheServer() async {
        let made = makeHost(approver: ScriptedApprover(.deny))
        let result = await made.host.execute(call("create_key"))
        XCTAssertTrue(result.isError)
        XCTAssertEqual(result.text, "The user did not allow this tool call.")
        XCTAssertFalse(MCPStubProtocol.requests(for: made.url).contains { $0.rpcMethod == "tools/call" })
    }

    func testAlwaysAllowIsRememberedPerTool() async {
        let permissions = ToolPermissionStore(defaults: testDefaults())
        let made = makeHost(approver: ScriptedApprover(.alwaysAllow), permissions: permissions)
        _ = await made.host.execute(call("create_key"))
        _ = await made.host.execute(call("create_key"))
        XCTAssertEqual(made.approver.requests.count, 1)
        XCTAssertTrue(permissions.isAlwaysAllowed(serverID: "alpha", toolName: "create_key"))
        XCTAssertFalse(permissions.isAlwaysAllowed(serverID: "alpha", toolName: "get_credits"))
    }

    func testBadCallsComeBackAsErrorResults() async {
        let host = makeHost().host
        let unknown = await host.execute(call("nope"))
        XCTAssertTrue(unknown.isError)
        XCTAssertEqual(unknown.text, "Unknown tool: nope.")
        let bad = await host.execute(call("get_credits", "[1,2]"))
        XCTAssertTrue(bad.isError)
        XCTAssertEqual(bad.text, "The arguments are not a JSON object.")
        // A model that sends no arguments for a tool without parameters is fine.
        let empty = await host.execute(call("get_credits", ""))
        XCTAssertFalse(empty.isError)
    }

    func testServerFailuresAndToolErrorsBecomeErrorResults() async {
        let toolError = makeHost(handler: standardMCPHandler { MCPFixtures.reply(MCPFixtures.callError, to: $0) })
        let first = await toolError.host.execute(call("get_credits"))
        XCTAssertTrue(first.isError)
        XCTAssertEqual(first.text, "Key key_123 not found in this workspace.")

        let down = makeHost(handler: standardMCPHandler { _ in StubResponse(status: 500, body: #"{"error":{"message":"boom"}}"#) })
        let second = await down.host.execute(call("get_credits"))
        XCTAssertTrue(second.isError)
        XCTAssertEqual(second.text, "HTTP 500: boom")
    }

    func testLongResultsAreCut() {
        let long = String(repeating: "a", count: MCPToolHost.maxResultCharacters + 50)
        let clipped = MCPToolHost.clip(long)
        XCTAssertTrue(clipped.hasPrefix(String(long.prefix(MCPToolHost.maxResultCharacters))))
        XCTAssertTrue(clipped.hasSuffix("[Result cut at 20000 characters.]"))
        XCTAssertEqual(MCPToolHost.clip("short"), "short")
    }

    func testNamesAreSanitizedAndCollisionsGetTheServerName() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/mcp"))
        let a = server("Alpha", url), b = server("Beta", url)
        let names = MCPToolHost.uniqueNames(for: [
            (server: a, tool: MCPTool(name: "search")),
            (server: b, tool: MCPTool(name: "search")),
            (server: a, tool: MCPTool(name: "web scrape!")),
        ])
        XCTAssertEqual(names, ["Alpha__search", "Beta__search", "web_scrape_"])
        XCTAssertEqual(MCPToolHost.sanitize(""), "tool")
        XCTAssertEqual(MCPToolHost.sanitize(String(repeating: "x", count: 100)).count, 64)

        // Even the prefixed names can collide; they still end up unique.
        let twins = MCPToolHost.uniqueNames(for: [
            (server: a, tool: MCPTool(name: "x")), (server: a, tool: MCPTool(name: "x")),
        ])
        XCTAssertEqual(Set(twins).count, 2)
    }

    func testPermissionStorePersistsAndRevokes() {
        let defaults = testDefaults()
        let store = ToolPermissionStore(defaults: defaults)
        store.allow(serverID: "s1", toolName: "a")
        store.allow(serverID: "s2", toolName: "a")
        XCTAssertTrue(ToolPermissionStore(defaults: defaults).isAlwaysAllowed(serverID: "s1", toolName: "a"))
        store.revoke(serverID: "s1", toolName: "a")
        XCTAssertFalse(store.isAlwaysAllowed(serverID: "s1", toolName: "a"))
        store.revokeAll(serverID: "s2")
        XCTAssertFalse(store.isAlwaysAllowed(serverID: "s2", toolName: "a"))
    }
}

@MainActor
final class IntegrationsToolHostTests: XCTestCase {
    func testStoreBuildsAHostFromEnabledToolsOnly() async throws {
        let store = IntegrationsStore(
            defaults: testDefaults(), credentials: FakeCredentialStore(),
            anyRouterToken: { nil }, session: MCPStubProtocol.session()
        )
        let approver = ScriptedApprover(.allowOnce)
        XCTAssertNil(store.makeToolHost(approver: approver), "nothing connected yet")

        let url = MCPStubProtocol.register(standardMCPHandler())
        let server = try store.addServer(name: "Alpha", urlString: url.absoluteString, token: "")
        await store.refresh(server)
        let tools = store.state(for: server).tools
        for tool in tools where tool.name != "get_credits" { store.setEnabled(false, tool: tool, on: server) }

        let host = try XCTUnwrap(store.makeToolHost(approver: approver))
        XCTAssertEqual(host.specs.map(\.name), ["get_credits"])
        let result = await host.execute(ToolCall(id: "c", name: "get_credits", argumentsJSON: "{}"))
        XCTAssertFalse(result.isError)

        store.setEnabled(false, tool: try XCTUnwrap(tools.first { $0.name == "get_credits" }), on: server)
        XCTAssertNil(store.makeToolHost(approver: approver))
    }

    func testRemovingAServerForgetsItsAlwaysAllowChoices() async throws {
        let store = IntegrationsStore(
            defaults: testDefaults(), credentials: FakeCredentialStore(),
            anyRouterToken: { nil }, session: MCPStubProtocol.session()
        )
        let server = try store.addServer(name: "Alpha", urlString: "https://example.com/mcp", token: "")
        store.permissions.allow(serverID: server.id, toolName: "create_key")
        store.removeServer(server)
        XCTAssertFalse(store.permissions.isAlwaysAllowed(serverID: server.id, toolName: "create_key"))
    }
}
