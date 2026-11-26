import Foundation

/// A remote MCP server the app can talk to over streamable HTTP.
struct MCPServer: Identifiable, Hashable, Codable, Sendable {
    enum Auth: String, Codable, Sendable {
        /// No credential.
        case none
        /// The AnyRouter sign-in token.
        case anyRouterSignIn
        /// A bearer token the user pasted, stored in the Keychain under the server id.
        case bearerToken
    }

    var id: String
    var name: String
    var url: URL
    var auth: Auth

    /// AnyRouter's own server. The sign-in token works against it.
    static let anyRouter = MCPServer(
        id: "anyrouter",
        name: "AnyRouter",
        url: URL(string: "https://mcp.anyrouter.dev/api/v1/mcp")!,
        auth: .anyRouterSignIn
    )
}

struct MCPTool: Identifiable, Hashable, Codable, Sendable {
    /// Behavior hints from the server. They are hints, not guarantees.
    struct Annotations: Hashable, Codable, Sendable {
        var title: String?
        var readOnlyHint: Bool?
        var destructiveHint: Bool?
        var idempotentHint: Bool?
        var openWorldHint: Bool?
    }

    var name: String
    var title: String?
    var description: String?
    /// JSON Schema of the arguments object.
    var inputSchema: JSONValue
    var annotations: Annotations?

    var id: String { name }
    var isReadOnly: Bool { annotations?.readOnlyHint == true }
    var displayName: String { title ?? annotations?.title ?? name }

    init(
        name: String,
        title: String? = nil,
        description: String? = nil,
        inputSchema: JSONValue = .object(["type": .string("object")]),
        annotations: Annotations? = nil
    ) {
        self.name = name
        self.title = title
        self.description = description
        self.inputSchema = inputSchema
        self.annotations = annotations
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        inputSchema = try container.decodeIfPresent(JSONValue.self, forKey: .inputSchema)
            ?? .object(["type": .string("object")])
        annotations = try container.decodeIfPresent(Annotations.self, forKey: .annotations)
    }
}

struct MCPToolResult: Hashable, Sendable {
    enum Content: Hashable, Sendable {
        case text(String)
        /// Base64 data.
        case image(data: String, mimeType: String)
        case resource(uri: String, mimeType: String?, text: String?)
        case unsupported(type: String)
    }

    var content: [Content]
    var structuredContent: JSONValue?
    var isError: Bool

    init(content: [Content], structuredContent: JSONValue? = nil, isError: Bool = false) {
        self.content = content
        self.structuredContent = structuredContent
        self.isError = isError
    }

    /// Parses the `result` object of a `tools/call` response.
    init(json: JSONValue) throws {
        guard json.object != nil else { throw MCPError.invalidResponse("tools/call result is not an object.") }
        let blocks = json["content"]?.array ?? []
        content = blocks.map(Self.content(from:))
        structuredContent = json["structuredContent"]
        isError = json["isError"]?.bool ?? false
    }

    private static func content(from block: JSONValue) -> Content {
        let type = block["type"]?.string ?? "unknown"
        switch type {
        case "text":
            return .text(block["text"]?.string ?? "")
        case "image":
            return .image(data: block["data"]?.string ?? "", mimeType: block["mimeType"]?.string ?? "image/png")
        case "resource":
            let resource = block["resource"]
            return .resource(
                uri: resource?["uri"]?.string ?? "",
                mimeType: resource?["mimeType"]?.string,
                text: resource?["text"]?.string
            )
        case "resource_link":
            return .resource(uri: block["uri"]?.string ?? "", mimeType: block["mimeType"]?.string, text: nil)
        default:
            return .unsupported(type: type)
        }
    }

    /// Text form handed back to a model: text blocks, embedded resource text, and placeholders for the rest.
    var text: String {
        let parts: [String] = content.compactMap { item in
            switch item {
            case .text(let value): return value
            case .image(_, let mimeType): return "[image: \(mimeType)]"
            case .resource(let uri, _, let text): return text ?? "[resource: \(uri)]"
            case .unsupported(let type): return "[\(type) content]"
            }
        }
        if parts.isEmpty, let structuredContent { return structuredContent.jsonString() }
        return parts.joined(separator: "\n")
    }
}

enum MCPError: LocalizedError, Equatable {
    case unauthorized
    case http(status: Int, message: String)
    case rpc(code: Int, message: String)
    case transport(String)
    case invalidResponse(String)
    /// The server forgot our session (HTTP 404). The client re-initializes once on its own.
    case sessionExpired

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "The server rejected the credentials (HTTP 401). Check the token or sign in again."
        case .http(let status, let message):
            return "HTTP \(status): \(message)"
        case .rpc(let code, let message):
            return "Server error \(code): \(message)"
        case .transport(let message):
            return message
        case .invalidResponse(let detail):
            return "The server did not answer like an MCP server. \(detail)"
        case .sessionExpired:
            return "The server ended the session."
        }
    }

    static func from(urlError error: URLError) -> MCPError {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
            return .transport("No internet connection.")
        case .cannotFindHost, .dnsLookupFailed:
            return .transport("The host was not found. Check the URL.")
        case .cannotConnectToHost:
            return .transport("Could not connect to the server.")
        case .timedOut:
            return .transport("The server did not respond in time.")
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
            .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid, .clientCertificateRejected:
            return .transport("The secure connection failed. Check the certificate and the URL.")
        default:
            return .transport(error.localizedDescription)
        }
    }
}
