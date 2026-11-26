import Foundation

/// Text of the files a user attached to the current chat. The attachments feature supplies it.
protocol AttachmentTextProviding: Sendable {
    func attachmentNames() async -> [String]
    /// Nil when no attachment has that name.
    func text(named name: String) async -> String?
}

struct ReadAttachmentTool: BuiltInTool {
    let name = "read_attachment"
    let title = "Read attachments"
    let summary = "Text of files attached to this chat"
    let description = "Read the text of a file the user attached to this chat. Call it without a name to list the attachments."
    let inputSchemaJSON = #"{"type":"object","properties":{"name":{"type":"string","description":"File name of the attachment"}}}"#

    let provider: any AttachmentTextProviding
    var maxCharacters = 20_000

    func run(_ arguments: JSONValue) async throws -> String {
        let names = await provider.attachmentNames()
        guard !names.isEmpty else { throw BuiltInToolError("There are no attachments in this chat.") }
        guard let wanted = arguments["name"]?.string, !wanted.isEmpty else {
            return "Attachments: " + names.joined(separator: ", ")
        }
        guard let text = await provider.text(named: wanted) else {
            throw BuiltInToolError("No attachment named \(wanted). Attachments: " + names.joined(separator: ", "))
        }
        return clippedText(text, limit: maxCharacters)
    }
}
