import Foundation

/// Minimal MCP client over streamable HTTP: initialize, tools/list, tools/call.
///
/// One actor per server. It keeps the session id the server hands out, negotiates the
/// protocol version, and re-initializes once when the server drops the session.
/// It never logs tokens or request bodies.
actor MCPClient {
    struct ServerInfo: Equatable, Sendable {
        var name: String
        var version: String
        var protocolVersion: String
    }

    static let requestedProtocolVersion = "2025-06-18"

    private let server: MCPServer
    private let token: @Sendable () -> String?
    private let session: URLSession
    private let clientName: String
    private let clientVersion: String

    private var sessionID: String?
    private var protocolVersion: String?
    private var info: ServerInfo?
    private var connecting: Task<ServerInfo, any Error>?
    private var lastID = 0

    init(
        server: MCPServer,
        token: @escaping @Sendable () -> String?,
        session: URLSession = .shared,
        clientName: String = "AnyRouter for iOS",
        clientVersion: String = "1"
    ) {
        self.server = server
        self.token = token
        self.session = session
        self.clientName = clientName
        self.clientVersion = clientVersion
    }

    // MARK: API

    @discardableResult
    func connect() async throws -> ServerInfo {
        if let info { return info }
        if let connecting { return try await connecting.value }
        let task = Task { try await self.initialize() }
        connecting = task
        defer { connecting = nil }
        let result = try await task.value
        info = result
        return result
    }

    func listTools() async throws -> [MCPTool] {
        var tools: [MCPTool] = []
        var cursor: String?
        for _ in 0..<20 {
            let params: JSONValue? = cursor.map { .object(["cursor": .string($0)]) }
            let result = try await rpc("tools/list", params: params, timeout: 30)
            let page = result["tools"]?.array ?? []
            for item in page {
                do {
                    tools.append(try item.decode(MCPTool.self))
                } catch {
                    throw MCPError.invalidResponse("A tool in the list has no name.")
                }
            }
            guard let next = result["nextCursor"]?.string, !next.isEmpty else { return tools }
            cursor = next
        }
        return tools
    }

    func callTool(name: String, arguments: JSONValue = .object([:])) async throws -> MCPToolResult {
        let params: JSONValue = .object(["name": .string(name), "arguments": arguments])
        let result = try await rpc("tools/call", params: params, timeout: 60)
        return try MCPToolResult(json: result)
    }

    /// Ends the server session. Best effort: servers may not support it.
    func close() async {
        guard let sessionID else { return }
        var request = baseRequest(timeout: 10)
        request.httpMethod = "DELETE"
        request.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id")
        _ = try? await session.data(for: request)
        reset()
    }

    // MARK: Protocol

    private func initialize() async throws -> ServerInfo {
        let params: JSONValue = .object([
            "protocolVersion": .string(Self.requestedProtocolVersion),
            "capabilities": .object([:]),
            "clientInfo": .object(["name": .string(clientName), "version": .string(clientVersion)]),
        ])
        let result = try await send(method: "initialize", params: params, timeout: 30)
        let negotiated = result["protocolVersion"]?.string ?? Self.requestedProtocolVersion
        protocolVersion = negotiated
        let serverInfo = result["serverInfo"]
        let summary = ServerInfo(
            name: serverInfo?["name"]?.string ?? server.name,
            version: serverInfo?["version"]?.string ?? "",
            protocolVersion: negotiated
        )
        // The server may reject the notification (it has no state to update); initialize already succeeded.
        _ = try? await post(
            body: .object(["jsonrpc": .string("2.0"), "method": .string("notifications/initialized")]),
            timeout: 10
        )
        return summary
    }

    private func rpc(_ method: String, params: JSONValue?, timeout: TimeInterval) async throws -> JSONValue {
        try await connect()
        do {
            return try await send(method: method, params: params, timeout: timeout)
        } catch MCPError.sessionExpired {
            reset()
            try await connect()
            return try await send(method: method, params: params, timeout: timeout)
        }
    }

    private func send(method: String, params: JSONValue?, timeout: TimeInterval) async throws -> JSONValue {
        lastID += 1
        let id = lastID
        var body: [String: JSONValue] = [
            "jsonrpc": .string("2.0"),
            "id": .number(Double(id)),
            "method": .string(method),
        ]
        if let params { body["params"] = params }
        let (data, response) = try await post(body: .object(body), timeout: timeout)
        let messages = try MCPWire.messages(data: data, contentType: response.value(forHTTPHeaderField: "Content-Type"))
        return try MCPWire.result(id: id, in: messages)
    }

    // MARK: HTTP

    private func baseRequest(timeout: TimeInterval) -> URLRequest {
        var request = URLRequest(url: server.url, timeoutInterval: timeout)
        if server.auth != .none, let token = token(), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func post(body: JSONValue, timeout: TimeInterval) async throws -> (Data, HTTPURLResponse) {
        var request = baseRequest(timeout: timeout)
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        if let protocolVersion { request.setValue(protocolVersion, forHTTPHeaderField: "MCP-Protocol-Version") }
        if let sessionID { request.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id") }

        let fetched: (Data, URLResponse)
        do {
            fetched = try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as URLError {
            throw MCPError.from(urlError: error)
        }
        let (data, response) = fetched
        guard let http = response as? HTTPURLResponse else { throw MCPError.invalidResponse("Not an HTTP response.") }
        if let id = http.value(forHTTPHeaderField: "Mcp-Session-Id"), !id.isEmpty { sessionID = id }
        switch http.statusCode {
        case 200..<300: return (data, http)
        case 401: throw MCPError.unauthorized
        case 404 where sessionID != nil: throw MCPError.sessionExpired
        default:
            throw MCPError.http(status: http.statusCode, message: AnyRouterError.message(from: data, status: http.statusCode))
        }
    }

    private func reset() {
        sessionID = nil
        protocolVersion = nil
        info = nil
    }
}
