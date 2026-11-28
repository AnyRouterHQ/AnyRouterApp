import Foundation

/// What a chat knows when it asks for its tools: the files attached in it, and what the user wrote and attached.
struct ToolContext: Sendable {
    var attachments: [ChatAttachment] = []
    /// The user's own words and the text of their attachments. Never the model's or a tool's output.
    var userTexts: [String] = []
    /// The model that will use the tools. Sets what is on by default and how much tool text it is given.
    var modelSource: ModelSource?
    /// The device has no connection: web tools are left out of the request.
    var isOffline = false
    /// Sources the user named with @ for this message. When set, only their tools are offered.
    var forcedSourceIDs: Set<String> = []
    /// The chat's memory tools (`memory`, `search_chats`): set by the chat for a cloud model while memory is on.
    var memoryTools: [any BuiltInTool] = []
    /// What the tools ask before a call that needs approval: set by the chat, which saves the run while the user decides.
    /// Nil leaves the app's own approver.
    var approver: (any ToolApproving)?
}
