import Foundation
import Observation

/// Connected tool servers, their tool lists, and the per-tool on/off switches.
///
/// AnyRouter's own server is always listed; it connects with the sign-in token.
/// Custom servers and their bearer tokens persist across launches (tokens in the Keychain).
@MainActor @Observable
final class IntegrationsStore {
    enum Status: Equatable {
        case idle
        case connecting
        case needsSignIn
        case connected
        case failed(String)
    }

    struct ServerState: Equatable {
        var status: Status = .idle
        var tools: [MCPTool] = []
    }

    struct TestSummary: Equatable {
        var serverName: String
        var toolCount: Int
    }

    private enum Key {
        static let servers = "integrations.servers"
        static let overrides = "integrations.toolOverrides"
    }

    private(set) var customServers: [MCPServer]
    private(set) var states: [String: ServerState] = [:]
    /// Tool switches the user changed. A tool with no entry is on.
    private(set) var overrides: [String: Bool]

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let credentials: any MCPCredentialStoring
    @ObservationIgnored private let anyRouterToken: @Sendable () -> String?
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private var clients: [String: MCPClient] = [:]
    /// "Always allow" choices for tools that are not read-only.
    @ObservationIgnored let permissions: ToolPermissionStore

    init(
        defaults: UserDefaults = .standard,
        credentials: any MCPCredentialStoring = MCPKeychainCredentialStore(),
        anyRouterToken: @escaping @Sendable () -> String?,
        session: URLSession = .shared,
        permissions: ToolPermissionStore? = nil
    ) {
        self.permissions = permissions ?? ToolPermissionStore(defaults: defaults)
        self.defaults = defaults
        self.credentials = credentials
        self.anyRouterToken = anyRouterToken
        self.session = session
        customServers = defaults.data(forKey: Key.servers)
            .flatMap { try? JSONDecoder().decode([MCPServer].self, from: $0) } ?? []
        overrides = defaults.dictionary(forKey: Key.overrides) as? [String: Bool] ?? [:]
    }

    var servers: [MCPServer] { [MCPServer.anyRouter] + customServers }

    func state(for server: MCPServer) -> ServerState { states[server.id] ?? ServerState() }

    // MARK: Connecting

    /// A Keychain read can block for seconds on a cold boot, so it never runs on the main thread.
    private func readAnyRouterToken() async -> String? {
        let read = anyRouterToken
        return await Task.detached(priority: .userInitiated) { read() }.value
    }

    /// Connects with a fresh session and reads the tool list.
    func refresh(_ server: MCPServer) async {
        if server.auth == .anyRouterSignIn, await readAnyRouterToken() == nil {
            clients[server.id] = nil
            states[server.id] = ServerState(status: .needsSignIn)
            return
        }
        states[server.id] = ServerState(status: .connecting, tools: state(for: server).tools)
        let client = makeClient(for: server)
        clients[server.id] = client
        let outcome: ServerState
        do {
            try await client.connect()
            outcome = ServerState(status: .connected, tools: try await client.listTools())
        } catch is CancellationError {
            outcome = ServerState(status: .idle, tools: state(for: server).tools)
        } catch MCPError.unauthorized where server.auth == .anyRouterSignIn {
            outcome = ServerState(status: .needsSignIn)
        } catch {
            outcome = ServerState(status: .failed(error.localizedDescription))
        }
        // Sign-out, removing the server or a newer refresh replaced this client while it connected: its answer is stale.
        guard clients[server.id] === client else { return }
        states[server.id] = outcome
    }

    /// Sign-in connects the built-in AnyRouter server with the same token; sign-out disconnects it at once and
    /// forgets its tools. The task is returned so tests can wait for the connection.
    @discardableResult
    func accountChanged(signedIn: Bool) -> Task<Void, Never>? {
        let server = MCPServer.anyRouter
        guard signedIn else {
            clients[server.id] = nil
            states[server.id] = ServerState(status: .needsSignIn)
            return nil
        }
        return Task { await refresh(server) }
    }

    func refreshAll() async {
        for server in servers { await refresh(server) }
    }

    /// Client for tool calls. Created on first use, replaced by `refresh`.
    func client(for server: MCPServer) -> MCPClient {
        if let existing = clients[server.id] { return existing }
        let client = makeClient(for: server)
        clients[server.id] = client
        return client
    }

    /// Checks a URL and optional token before the server is saved.
    func testConnection(urlString: String, token: String) async -> Result<TestSummary, any Error> {
        let url: URL
        switch IntegrationsLogic.validate(urlString) {
        case .success(let value): url = value
        case .failure(let problem): return .failure(problem)
        }
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let probe = MCPServer(id: "probe", name: "probe", url: url, auth: trimmed.isEmpty ? .none : .bearerToken)
        let client = MCPClient(server: probe, token: { trimmed }, session: session)
        do {
            let info = try await client.connect()
            let tools = try await client.listTools()
            await client.close()
            return .success(TestSummary(serverName: info.name, toolCount: tools.count))
        } catch {
            return .failure(error)
        }
    }

    // MARK: Custom servers

    @discardableResult
    func addServer(name: String, urlString: String, token: String) throws -> MCPServer {
        let url: URL
        switch IntegrationsLogic.validate(urlString) {
        case .success(let value): url = value
        case .failure(let problem): throw problem
        }
        if customServers.contains(where: { $0.url == url }) { throw IntegrationsLogic.URLProblem.duplicate }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let server = MCPServer(
            id: UUID().uuidString.lowercased(),
            name: trimmedName.isEmpty ? IntegrationsLogic.defaultName(for: url) : trimmedName,
            url: url,
            auth: trimmedToken.isEmpty ? .none : .bearerToken
        )
        if !trimmedToken.isEmpty, !credentials.save(token: trimmedToken, for: server.id) {
            throw IntegrationsLogic.URLProblem.keychain
        }
        customServers.append(server)
        persistServers()
        return server
    }

    func removeServer(_ server: MCPServer) {
        guard server.id != MCPServer.anyRouter.id else { return }
        credentials.remove(for: server.id)
        permissions.revokeAll(serverID: server.id)
        customServers.removeAll { $0.id == server.id }
        states[server.id] = nil
        clients[server.id] = nil
        overrides = overrides.filter { !$0.key.hasPrefix(server.id + "/") }
        persistServers()
        persistOverrides()
    }

    // MARK: Tool switches

    func isEnabled(_ tool: MCPTool, on server: MCPServer) -> Bool {
        overrides[IntegrationsLogic.toolKey(serverID: server.id, toolName: tool.name)] ?? server.enabledByDefault(tool)
    }

    func setEnabled(_ enabled: Bool, tool: MCPTool, on server: MCPServer) {
        let key = IntegrationsLogic.toolKey(serverID: server.id, toolName: tool.name)
        // Only a choice that differs from the default is stored.
        overrides[key] = enabled == server.enabledByDefault(tool) ? nil : enabled
        persistOverrides()
    }

    /// Tools of connected servers that the user left on.
    var enabledTools: [(server: MCPServer, tool: MCPTool)] {
        servers.flatMap { server -> [(server: MCPServer, tool: MCPTool)] in
            let state = state(for: server)
            guard state.status == .connected else { return [] }
            return state.tools.filter { isEnabled($0, on: server) }.map { (server: server, tool: $0) }
        }
    }

    /// Tool host for one chat request, or nil when no connected server has a tool turned on.
    func makeToolHost(approver: any ToolApproving) -> MCPToolHost? {
        makeToolHost(enabled: enabledTools, approver: approver)
    }

    /// Same for a chosen list of tools. `reserved` are names other tool sources already use.
    func makeToolHost(
        enabled: [(server: MCPServer, tool: MCPTool)],
        approver: any ToolApproving,
        reserved: Set<String> = []
    ) -> MCPToolHost? {
        guard !enabled.isEmpty else { return nil }
        return MCPToolHost(
            enabled: enabled,
            client: { self.client(for: $0) },
            approver: approver,
            permissions: permissions,
            reserved: reserved
        )
    }

    // MARK: Helpers

    private func makeClient(for server: MCPServer) -> MCPClient {
        let provider: (@Sendable () -> String?)?
        switch server.auth {
        case .none: provider = nil
        case .anyRouterSignIn: provider = anyRouterToken
        case .bearerToken:
            let credentials = credentials
            let id = server.id
            provider = { credentials.token(for: id) }
        }
        return MCPClient(server: server, token: provider, session: session)
    }

    private func persistServers() {
        defaults.set(try? JSONEncoder().encode(customServers), forKey: Key.servers)
    }

    private func persistOverrides() {
        defaults.set(overrides, forKey: Key.overrides)
    }
}
