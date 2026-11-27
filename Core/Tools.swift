import Foundation

/// A tool a model may call. Engines turn it into their own wire format.
struct ToolSpec: Identifiable, Hashable, Codable, Sendable {
    /// Unique within one request. Letters, digits, `_` and `-`, at most 64 characters.
    var name: String
    var title: String?
    var description: String
    /// JSON Schema of the arguments object, as JSON text.
    var inputSchemaJSON: String
    /// What running the tool can change. The tool host's approvals follow it.
    var sideEffect: ToolSideEffect

    var id: String { name }
    /// The tool only reads: no approval of its own, but the exfiltration guard still checks what it sends.
    var isReadOnly: Bool { sideEffect.isRead }
}

extension ToolSpec {
    /// A tool known only as read-only or not, as an MCP server marks it: anything that is not read-only acts on the server.
    init(name: String, title: String?, description: String, inputSchemaJSON: String, isReadOnly: Bool) {
        self.init(name: name, title: title, description: description, inputSchemaJSON: inputSchemaJSON, sideEffect: isReadOnly ? .read : .external)
    }
}

/// The side-effect class of a tool (PLAN LA1).
enum ToolSideEffect: String, Codable, CaseIterable, Sendable {
    /// Reads nothing private and changes nothing. Runs without asking.
    case read
    /// Reads the user's own data, such as other chats. Runs without asking; what it read is the user's.
    case sensitiveRead
    /// Changes data in the app or on the device. Asked every time, never "always allowed".
    case write
    /// Acts outside the app: sends something or changes a server. Asked every time, never "always allowed".
    case external

    var isRead: Bool { self == .read || self == .sensitiveRead }
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

    /// What a tool host answers when the user denies a call. The chat reads it back to show the call as denied.
    static let deniedText = "The user did not allow this tool call."
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
    /// The id of the source a tool comes from (the app's own tools, a public service, AnyRouter, a custom server), so
    /// a reply can show that source's icon. Nil when the host cannot say.
    func sourceID(forTool name: String) -> String?
}

extension ToolHost {
    func sourceID(forTool name: String) -> String? { nil }
}

/// One call and its outcome, as shown in a message and kept with the assistant reply.
struct ToolStep: Identifiable, Hashable, Codable, Sendable {
    var call: ToolCall
    /// Nil while the call is still running.
    var result: ToolResult?
    /// The source that ran the call, noted when the call was made. Nil for replies saved before this existed.
    var sourceID: String?
    /// The calls a subagent made while this one ran, in order. Nil for a plain call and for replies saved before this existed.
    var children: [ToolStep]?

    var id: String { call.id }
}
