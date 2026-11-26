import XCTest

@testable import AnyRouter

@MainActor
final class IntegrationsStoreTests: XCTestCase {
    private func makeStore(
        defaults: UserDefaults? = nil,
        credentials: FakeCredentialStore = FakeCredentialStore(),
        token: String? = "tok"
    ) -> IntegrationsStore {
        IntegrationsStore(
            defaults: defaults ?? testDefaults(),
            credentials: credentials,
            anyRouterToken: { token },
            session: MCPStubProtocol.session()
        )
    }

    /// AnyRouter's real server is a fixed URL, so tests exercise the store through custom servers.
    private func addServer(_ store: IntegrationsStore, handler: @escaping @Sendable (RecordedRequest) -> StubResponse = standardMCPHandler(), token: String = "") throws -> MCPServer {
        let url = MCPStubProtocol.register(handler)
        return try store.addServer(name: "", urlString: url.absoluteString, token: token)
    }

    func testKeychainFailureMeansTheServerIsNotAddedWithoutItsToken() {
        let credentials = FakeCredentialStore()
        credentials.failsSaves = true
        let store = makeStore(credentials: credentials)
        XCTAssertThrowsError(try store.addServer(name: "x", urlString: "https://example.com/mcp", token: "secret")) {
            XCTAssertEqual($0 as? IntegrationsLogic.URLProblem, .keychain)
        }
        XCTAssertTrue(store.customServers.isEmpty)
        // A server without a token needs no Keychain write.
        XCTAssertNoThrow(try store.addServer(name: "open", urlString: "https://open.example.com/mcp", token: ""))
    }

    func testAnyRouterIsListedFirstAndNeedsSignInWithoutAToken() async {
        let store = makeStore(token: nil)
        XCTAssertEqual(store.servers.first, .anyRouter)
        XCTAssertEqual(MCPServer.anyRouter.url.absoluteString, "https://anyrouter.dev/api/v1/mcp")
        await store.refresh(.anyRouter)
        XCTAssertEqual(store.state(for: .anyRouter).status, .needsSignIn)
        XCTAssertTrue(store.state(for: .anyRouter).tools.isEmpty)
    }

    func testRefreshLoadsTools() async throws {
        let store = makeStore()
        let server = try addServer(store)
        await store.refresh(server)
        XCTAssertEqual(store.state(for: server).status, .connected)
        XCTAssertEqual(store.state(for: server).tools.count, 5)
    }

    func testRefreshFailureShowsTheReason() async throws {
        let store = makeStore()
        let server = try addServer(store) { _ in StubResponse(status: 500, body: #"{"error":{"message":"upstream down"}}"#) }
        await store.refresh(server)
        XCTAssertEqual(store.state(for: server).status, .failed("HTTP 500: upstream down"))
    }

    func testCustomServerSendsItsSavedBearerToken() async throws {
        let store = makeStore()
        let server = try addServer(store, token: " secret-1 ")
        XCTAssertEqual(server.auth, .bearerToken)
        await store.refresh(server)
        let seen = MCPStubProtocol.requests(for: server.url)
        XCTAssertEqual(seen.first?.header("Authorization"), "Bearer secret-1")
    }

    func testToolSwitchesDefaultOnAndPersist() async throws {
        let defaults = testDefaults()
        let store = makeStore(defaults: defaults)
        let server = try addServer(store)
        await store.refresh(server)
        let tools = store.state(for: server).tools
        let credits = try XCTUnwrap(tools.first { $0.name == "get_credits" })
        XCTAssertTrue(store.isEnabled(credits, on: server))

        store.setEnabled(false, tool: credits, on: server)
        XCTAssertFalse(store.isEnabled(credits, on: server))
        XCTAssertFalse(store.enabledTools.contains { $0.tool.name == "get_credits" })
        XCTAssertEqual(store.enabledTools.count, 4)

        // A new store on the same defaults sees the switch and the server.
        let reopened = makeStore(defaults: defaults)
        XCTAssertEqual(reopened.customServers, [server])
        XCTAssertFalse(reopened.isEnabled(credits, on: server))

        store.setEnabled(true, tool: credits, on: server)
        XCTAssertTrue(makeStore(defaults: defaults).isEnabled(credits, on: server))
    }

    func testEnabledToolsSkipServersThatAreNotConnected() async throws {
        let store = makeStore()
        let server = try addServer(store)
        XCTAssertTrue(store.enabledTools.isEmpty)
        await store.refresh(server)
        XCTAssertEqual(store.enabledTools.count, 5)
    }

    func testRemoveServerDeletesTokenAndSwitches() async throws {
        let credentials = FakeCredentialStore()
        let store = makeStore(credentials: credentials)
        let server = try addServer(store, token: "secret")
        XCTAssertEqual(credentials.token(for: server.id), "secret")
        await store.refresh(server)
        let tool = try XCTUnwrap(store.state(for: server).tools.first)
        store.setEnabled(false, tool: tool, on: server)

        store.removeServer(server)
        XCTAssertNil(credentials.token(for: server.id))
        XCTAssertTrue(store.customServers.isEmpty)
        XCTAssertTrue(store.overrides.isEmpty)
        store.removeServer(.anyRouter)
        XCTAssertEqual(store.servers, [.anyRouter])
    }

    func testAddServerRejectsBadAndDuplicateURLs() throws {
        let store = makeStore()
        XCTAssertThrowsError(try store.addServer(name: "x", urlString: "  ", token: "")) {
            XCTAssertEqual($0 as? IntegrationsLogic.URLProblem, .empty)
        }
        XCTAssertThrowsError(try store.addServer(name: "x", urlString: "http://example.com/mcp", token: "")) {
            XCTAssertEqual($0 as? IntegrationsLogic.URLProblem, .notHTTPS)
        }
        _ = try store.addServer(name: "x", urlString: "https://example.com/mcp", token: "")
        XCTAssertThrowsError(try store.addServer(name: "y", urlString: "https://example.com/mcp", token: "")) {
            XCTAssertEqual($0 as? IntegrationsLogic.URLProblem, .duplicate)
        }
        XCTAssertEqual(store.customServers.count, 1)
    }

    func testConnectionTestReportsToolCountOrTheError() async throws {
        let store = makeStore()
        let good = MCPStubProtocol.register(standardMCPHandler())
        switch await store.testConnection(urlString: good.absoluteString, token: "") {
        case .success(let summary): XCTAssertEqual(summary, .init(serverName: "anyrouter-mcp", toolCount: 5))
        case .failure(let error): XCTFail("\(error)")
        }

        let denied = MCPStubProtocol.register { _ in StubResponse(status: 401, body: "{}") }
        switch await store.testConnection(urlString: denied.absoluteString, token: "bad") {
        case .success: XCTFail("expected failure")
        case .failure(let error): XCTAssertEqual(error as? MCPError, .unauthorized)
        }

        switch await store.testConnection(urlString: "not a url", token: "") {
        case .success: XCTFail("expected failure")
        case .failure(let error): XCTAssertNotNil(error as? IntegrationsLogic.URLProblem)
        }
    }
}

/// Mutable token the store reads, like the Keychain.
private final class TokenBox: @unchecked Sendable {
    private let lock = NSLock()
    private var current: String?
    var token: String? {
        get { lock.withLock { current } }
        set { lock.withLock { current = newValue } }
    }
}

@MainActor
private struct ImmediateSigner: OAuthSigning {
    func signIn() async throws -> IssuedToken { IssuedToken(accessToken: "sk-ar-live", expiresAt: nil) }
}

@MainActor
final class AnyRouterSignInConnectTests: XCTestCase {
    private func makeStore(_ box: TokenBox) -> IntegrationsStore {
        IntegrationsStore(
            defaults: testDefaults(), credentials: FakeCredentialStore(),
            anyRouterToken: { box.token }, session: MCPStubProtocol.session()
        )
    }

    private func serveAnyRouter() {
        MCPStubProtocol.register(host: MCPServer.anyRouter.url.host()!, standardMCPHandler())
    }

    func testSignInConnectsWithTheSameTokenAndSignOutDisconnects() async throws {
        serveAnyRouter()
        let box = TokenBox()
        let store = makeStore(box)
        XCTAssertEqual(store.state(for: .anyRouter).status, .idle)

        box.token = "sk-ar-live"
        await store.accountChanged(signedIn: true)?.value
        XCTAssertEqual(store.state(for: .anyRouter).status, .connected)
        XCTAssertEqual(store.state(for: .anyRouter).tools.count, 5)
        // create_key does not read, so AnyRouter's own server starts with it off.
        XCTAssertEqual(store.enabledTools.count, 4)
        let seen = MCPStubProtocol.requests(for: MCPServer.anyRouter.url)
        XCTAssertEqual(seen.first?.header("Authorization"), "Bearer sk-ar-live")

        box.token = nil
        store.accountChanged(signedIn: false)
        XCTAssertEqual(store.state(for: .anyRouter).status, .needsSignIn)
        XCTAssertTrue(store.state(for: .anyRouter).tools.isEmpty)
        XCTAssertTrue(store.enabledTools.isEmpty)
        XCTAssertNil(store.makeToolHost(approver: NeverAsked()))
    }

    /// The test host's Keychain may refuse writes (the auth tests hit the same wall); then these tests have nothing to say.
    private func workingKeychain() throws -> KeychainStore {
        let keychain = KeychainStore(service: "dev.anyrouter.tests.\(UUID().uuidString)")
        try XCTSkipUnless(keychain.save(token: "probe", expiresAt: nil), "this host's Keychain refuses writes")
        keychain.clear()
        return keychain
    }

    func testSignedInStateFlowsFromTheAuthToTheStore() async throws {
        serveAnyRouter()
        let keychain = try workingKeychain()
        defer { keychain.clear() }
        let store = IntegrationsStore(
            defaults: testDefaults(), credentials: FakeCredentialStore(),
            anyRouterToken: { keychain.token() }, session: MCPStubProtocol.session()
        )
        let auth = AnyRouterAuth(store: keychain, client: ImmediateSigner())
        auth.onSignedInChange = { _ = store.accountChanged(signedIn: $0) }

        await auth.signIn()
        let connected = await waitUntil { store.state(for: .anyRouter).status == .connected }
        XCTAssertTrue(connected)
        XCTAssertEqual(store.state(for: .anyRouter).tools.count, 5)

        auth.signOut()
        XCTAssertEqual(store.state(for: .anyRouter).status, .needsSignIn)
        XCTAssertTrue(store.state(for: .anyRouter).tools.isEmpty)

        // A server that turns the token down (revoked key) also ends as signed out.
        MCPStubProtocol.register(host: MCPServer.anyRouter.url.host()!) { _ in StubResponse(status: 401, body: "{}") }
        keychain.save(token: "sk-ar-revoked", expiresAt: nil)
        await store.refresh(.anyRouter)
        XCTAssertEqual(store.state(for: .anyRouter).status, .needsSignIn)
    }

    func testAuthReportsOnlyRealChanges() async throws {
        let keychain = try workingKeychain()
        defer { keychain.clear() }
        let auth = AnyRouterAuth(store: keychain, client: ImmediateSigner())
        var changes: [Bool] = []
        auth.onSignedInChange = { changes.append($0) }
        auth.refresh()
        await auth.signIn()
        auth.refresh()
        auth.handleUnauthorized()
        XCTAssertEqual(changes, [true, false])
    }
}

private struct NeverAsked: ToolApproving {
    func decide(_ request: ToolApprovalRequest) async -> ToolDecision { .deny }
}

final class IntegrationsLogicTests: XCTestCase {
    func testValidate() {
        XCTAssertEqual(try? IntegrationsLogic.validate("https://mcp.example.com/mcp").get().absoluteString, "https://mcp.example.com/mcp")
        XCTAssertEqual(try? IntegrationsLogic.validate("mcp.example.com/mcp").get().absoluteString, "https://mcp.example.com/mcp")
        XCTAssertEqual(try? IntegrationsLogic.validate("http://localhost:8787/mcp").get().port, 8787)
        XCTAssertEqual(IntegrationsLogic.validate("http://example.com").failureValue, .notHTTPS)
        XCTAssertEqual(IntegrationsLogic.validate("ftp://example.com").failureValue, .invalid)
        XCTAssertEqual(IntegrationsLogic.validate("").failureValue, .empty)
    }

    func testDefaultNameDropsMCPPrefix() throws {
        XCTAssertEqual(IntegrationsLogic.defaultName(for: try XCTUnwrap(URL(string: "https://mcp.example.com/x"))), "example.com")
        XCTAssertEqual(IntegrationsLogic.defaultName(for: try XCTUnwrap(URL(string: "https://tools.example.com"))), "tools.example.com")
    }

    func testToolKeyIsPerServer() {
        XCTAssertNotEqual(
            IntegrationsLogic.toolKey(serverID: "a", toolName: "search"),
            IntegrationsLogic.toolKey(serverID: "b", toolName: "search")
        )
    }
}

private extension Result {
    var failureValue: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
