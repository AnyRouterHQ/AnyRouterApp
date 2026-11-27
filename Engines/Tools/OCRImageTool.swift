import Foundation

/// Reads the text in the chat's photos again, from the stored image, with tables kept as rows. `read_attachment` returns
/// the text saved when the photo was attached; this one runs a fresh pass on the image itself.
struct OCRImageTool: BuiltInTool {
    static let toolName = "ocr_image"
    /// Images read in one call when the model names none: the newest ones.
    static let maxImages = 4

    let name = OCRImageTool.toolName
    let title = "Read text in photos"
    let summary = "Text and tables in photos attached to this chat"
    let description = "Read the text in a photo attached to this chat, with tables kept as rows. Call it without a name to read the newest photos."
    let inputSchemaJSON = #"{"type":"object","properties":{"name":{"type":"string","description":"File name of the photo"}}}"#

    /// The chat's image attachments, oldest first.
    let images: [ChatAttachment]
    var store: AttachmentStore = .shared
    var reader: any ImageTextReading = VisionTextReader()
    var maxCharacters = 20_000

    func run(_ arguments: JSONValue) async throws -> String {
        guard !images.isEmpty else { throw BuiltInToolError("There are no photos in this chat.") }
        var chosen = Array(images.suffix(Self.maxImages))
        var parts: [String] = []
        if let wanted = arguments["name"]?.string, !wanted.isEmpty {
            guard let found = images.first(where: { $0.filename.caseInsensitiveCompare(wanted) == .orderedSame }) else {
                throw BuiltInToolError("No photo named \(wanted). Photos: " + images.map(\.filename).joined(separator: ", "))
            }
            chosen = [found]
        } else if images.count > Self.maxImages {
            parts.append("Read the newest \(Self.maxImages) of \(images.count) photos. Name one to read another.")
        }
        for image in chosen {
            try Task.checkCancellation()
            let text: String
            if let data = store.data(for: image) {
                let read = try await reader.read(data)
                text = read.isEmpty ? "No text found." : read.rendered
            } else {
                text = "The photo file is missing."
            }
            parts.append("[\(image.filename)]\n\(text)")
        }
        return clippedText(parts.joined(separator: "\n\n"), limit: maxCharacters)
    }
}
