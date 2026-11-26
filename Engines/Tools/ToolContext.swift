import Foundation

/// What a chat knows when it asks for its tools: the files attached in it, and what the user wrote and attached.
struct ToolContext: Sendable {
    var attachments: [ChatAttachment] = []
    /// The user's own words and the text of their attachments. Never the model's or a tool's output.
    var userTexts: [String] = []
}
