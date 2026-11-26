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
}
