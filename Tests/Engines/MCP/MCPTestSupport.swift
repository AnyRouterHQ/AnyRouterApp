import Foundation

@testable import AnyRouter

/// A canned HTTP response.
struct StubResponse: Sendable {
    var status = 200
    var headers: [String: String] = ["Content-Type": "application/json"]
    var body: Data

    init(status: Int = 200, headers: [String: String] = ["Content-Type": "application/json"], body: String = "") {
        self.status = status
        self.headers = headers
        self.body = Data(body.utf8)
    }

    static func json(_ body: String, headers: [String: String] = [:]) -> StubResponse {
        StubResponse(headers: ["Content-Type": "application/json"].merging(headers) { $1 }, body: body)
    }

    static func sse(_ body: String, headers: [String: String] = [:]) -> StubResponse {
        StubResponse(headers: ["Content-Type": "text/event-stream"].merging(headers) { $1 }, body: body)
    }
}

/// What the stub saw.
struct RecordedRequest: Sendable {
    var method: String
    var headers: [String: String]
    var body: JSONValue?

    var rpcMethod: String? { body?["method"]?.string }
    func header(_ name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

/// Serves canned responses per host so tests do not touch the network or each other.
final class MCPStubProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var handlers: [String: @Sendable (RecordedRequest) -> StubResponse] = [:]
    nonisolated(unsafe) private static var recorded: [String: [RecordedRequest]] = [:]

    /// Registers a handler for a fresh host and returns the server URL.
    static func register(_ handler: @escaping @Sendable (RecordedRequest) -> StubResponse) -> URL {
        let host = "mcp-\(UUID().uuidString.lowercased()).test"
        lock.withLock { handlers[host] = handler }
        return URL(string: "https://\(host)/mcp")!
    }

    /// Registers a handler for an existing host, such as AnyRouter's own server URL. Tests that do this run one at a time.
    static func register(host: String, _ handler: @escaping @Sendable (RecordedRequest) -> StubResponse) {
        lock.withLock {
            handlers[host] = handler
            recorded[host] = []
        }
    }

    static func requests(for url: URL) -> [RecordedRequest] {
        lock.withLock { recorded[url.host() ?? ""] ?? [] }
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MCPStubProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let host = request.url?.host() ?? ""
        let recordedRequest = RecordedRequest(
            method: request.httpMethod ?? "GET",
            headers: request.allHTTPHeaderFields ?? [:],
            body: Self.bodyData(of: request).flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) }
        )
        let handler = Self.lock.withLock { () -> (@Sendable (RecordedRequest) -> StubResponse)? in
            Self.recorded[host, default: []].append(recordedRequest)
            return Self.handlers[host]
        }
        let stub = handler?(recordedRequest) ?? StubResponse(status: 500, body: "no handler")
        let response = HTTPURLResponse(url: request.url!, statusCode: stub.status, httpVersion: "HTTP/1.1", headerFields: stub.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func bodyData(of request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

/// In-memory token store.
final class FakeCredentialStore: MCPCredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: [String: String] = [:]

    func token(for serverID: String) -> String? { lock.withLock { tokens[serverID] } }
    /// When set, `save` fails like a locked Keychain.
    var failsSaves = false

    func save(token: String, for serverID: String) -> Bool {
        lock.withLock {
            if failsSaves { return false }
            tokens[serverID] = token
            return true
        }
    }
    func remove(for serverID: String) { lock.withLock { tokens[serverID] = nil } }
}

extension StubResponse {
    /// The same JSON with trailing spaces, so a size cap has something to refuse.
    func withPadding(_ bytes: Int) -> StubResponse {
        var copy = self
        copy.body.append(Data(repeating: 0x20, count: bytes))
        return copy
    }
}

private final class MCPFixtureAnchor {}

extension MCPFixtures {
    /// A real `tools/list` answer of AnyRouter's MCP server for a sign-in token: 31 tools, 26 of them Firecrawl.
    static var anyRouterToolsList: String {
        guard let url = Bundle(for: MCPFixtureAnchor.self).url(forResource: "anyrouter-tools-list", withExtension: "json"),
            let text = try? String(contentsOf: url, encoding: .utf8)
        else { fatalError("Missing the anyrouter-tools-list.json fixture in the test bundle") }
        return text
    }
}

/// Recorded-shape fixtures. The tool names and fields follow AnyRouter's MCP reference.
enum MCPFixtures {
    /// Answers `request` with `body`, rewriting the JSON-RPC id so tests do not depend on call order.
    static func reply(_ body: String, to request: RecordedRequest, headers: [String: String] = [:], sse: Bool = false) -> StubResponse {
        guard var message = JSONValue.parse(body)?.object, let id = request.body?["id"] else {
            return .json(body, headers: headers)
        }
        message["id"] = id
        let text = JSONValue.object(message).jsonString()
        return sse ? .sse("event: message\ndata: \(text)\n\n", headers: headers) : .json(text, headers: headers)
    }

    static let initialize = """
        {"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-06-18","capabilities":{"tools":{"listChanged":false}},"serverInfo":{"name":"anyrouter-mcp","version":"1.4.0"}}}
        """

    static let toolsList = """
        {"jsonrpc":"2.0","id":2,"result":{"tools":[
          {"name":"list_models","description":"Browse models your key can call.","inputSchema":{"type":"object","properties":{"provider":{"type":"string"},"free_only":{"type":"boolean"},"limit":{"type":"number"}}},"annotations":{"readOnlyHint":true,"title":"List models"}},
          {"name":"recommend_model","description":"Rank models for one job.","inputSchema":{"type":"object","properties":{"task":{"type":"string"}},"required":["task"]},"annotations":{"readOnlyHint":true}},
          {"name":"get_credits","description":"Workspace balance and lifetime usage totals.","inputSchema":{"type":"object","properties":{}},"annotations":{"readOnlyHint":true,"openWorldHint":false}},
          {"name":"get_system_status","inputSchema":{"type":"object"}},
          {"name":"create_key","title":"Create key","description":"Create a new LLM API key.","inputSchema":{"type":"object","properties":{"name":{"type":"string"}},"required":["name"]},"annotations":{"readOnlyHint":false,"destructiveHint":false}}
        ]}}
        """

    static let callText = """
        {"jsonrpc":"2.0","id":3,"result":{"content":[{"type":"text","text":"{\\"total\\":1,\\"data\\":[{\\"id\\":\\"openai/gpt-5\\"}]}"}]}}
        """

    static let callError = """
        {"jsonrpc":"2.0","id":3,"result":{"content":[{"type":"text","text":"Key key_123 not found in this workspace."}],"isError":true}}
        """

    static let callMixed = """
        {"jsonrpc":"2.0","id":3,"result":{"content":[
          {"type":"text","text":"Found 2 pages."},
          {"type":"image","data":"aGVsbG8=","mimeType":"image/png"},
          {"type":"resource","resource":{"uri":"file:///notes.md","mimeType":"text/markdown","text":"# Notes"}},
          {"type":"resource_link","uri":"https://example.com/a","name":"a"},
          {"type":"audio","data":"AAAA","mimeType":"audio/wav"}
        ]}}
        """
}

/// Standard handler: answers initialize, tools/list and tools/call with the fixtures above.
func standardMCPHandler(
    sessionID: String? = "sess-1",
    toolCall: @escaping @Sendable (RecordedRequest) -> StubResponse = { MCPFixtures.reply(MCPFixtures.callText, to: $0) }
) -> @Sendable (RecordedRequest) -> StubResponse {
    { request in
        switch request.rpcMethod {
        case "initialize":
            return MCPFixtures.reply(MCPFixtures.initialize, to: request, headers: sessionID.map { ["Mcp-Session-Id": $0] } ?? [:])
        case "notifications/initialized":
            return StubResponse(status: 202, headers: [:], body: "")
        case "tools/list":
            return MCPFixtures.reply(MCPFixtures.toolsList, to: request)
        case "tools/call":
            return toolCall(request)
        default:
            return StubResponse(status: 400, body: "{\"error\":{\"message\":\"unexpected\"}}")
        }
    }
}
