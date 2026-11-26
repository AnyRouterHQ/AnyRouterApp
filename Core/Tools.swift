import Foundation

/// A tool a model may call. Engines turn it into their own wire format.
struct ToolSpec: Identifiable, Hashable, Codable, Sendable {
    /// Unique within one request. Letters, digits, `_` and `-`, at most 64 characters.
    var name: String
    var title: String?
    var description: String
    /// JSON Schema of the arguments object, as JSON text.
    var inputSchemaJSON: String
    /// False when the server did not mark the tool read-only: the user is asked before it runs.
    var isReadOnly: Bool

    var id: String { name }
}

struct ToolCall: Identifiable, Hashable, Codable, Sendable {
    var id: String
    var name: String
    /// The arguments object as JSON text, exactly as the model produced it.
    var argumentsJSON: String
}

struct ToolResult: Hashable, Codable, Sendable {
    var callID: String
    var name: String
    var text: String
    var isError: Bool
}

enum ToolDecision: String, Codable, Sendable {
    case allowOnce, alwaysAllow, deny
}

/// What an engine's agent loop may call. The host owns tool discovery, approval and execution.
protocol ToolHost: Sendable {
    /// Enabled tools for this request.
    var specs: [ToolSpec] { get }
    /// Runs one call, asking the user first when the tool needs approval. It never throws: a denial,
    /// a server failure or a cancelled call comes back as a result with `isError` set.
    func execute(_ call: ToolCall) async -> ToolResult
}

/// One call and its outcome, as shown in a message and kept with the assistant reply.
struct ToolStep: Identifiable, Hashable, Codable, Sendable {
    var call: ToolCall
    /// Nil while the call is still running.
    var result: ToolResult?

    var id: String { call.id }
}
