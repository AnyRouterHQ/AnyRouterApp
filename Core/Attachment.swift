import Foundation
import UniformTypeIdentifiers

/// A file, photo or document attached to a user message. The bytes live in the attachments folder
/// (see `AttachmentStore`); SwiftData keeps only this description.
struct Attachment: Identifiable, Hashable, Codable, Sendable {
    enum Kind: String, Codable, Sendable { case image, pdf, text, audio }

    var id: UUID
    var kind: Kind
    var filename: String
    /// Uniform type identifier of the stored file, e.g. `public.jpeg`.
    var utType: String
    var byteCount: Int64
    /// Path of the stored file under the attachments folder: `<thread id>/<id>.<ext>`, or `_pending/...`
    /// before the first send. Relative because the app container path changes when the app is updated.
    var relativePath: String
    /// Text read on device: a PDF's text, a text file's contents, or what OCR found in an image.
    var extractedText: String?
    /// `extractedText` came from OCR, not from the file itself.
    var isOCR = false
    /// `extractedText` was cut at `AttachmentPrompt.maxCharacters`.
    var isTruncated = false

    func url(in root: URL) -> URL { root.appending(path: relativePath) }

    var mimeType: String { UTType(utType)?.preferredMIMEType ?? "application/octet-stream" }
}

/// How an attachment reaches a model that cannot take the file itself: as text inside the message.
enum AttachmentPrompt {
    /// Longest extracted text kept per attachment.
    static let maxCharacters = 100_000

    /// The message text plus every attachment as text. `sendsImages` is true when the engine sends images
    /// natively, so image attachments add nothing here.
    static func text(for message: ChatMessage, sendsImages: Bool) -> String {
        var parts: [String] = []
        if !message.content.isEmpty { parts.append(message.content) }
        for attachment in message.attachments where !(sendsImages && attachment.kind == .image) {
            parts.append(block(attachment))
        }
        return parts.joined(separator: "\n\n")
    }

    private static func block(_ attachment: Attachment) -> String {
        let name = attachment.filename
        if let text = attachment.extractedText, !text.isEmpty {
            let source = attachment.isOCR ? " (text read from the image)" : ""
            let cut = attachment.isTruncated ? "\n[Text cut at \(maxCharacters) characters]" : ""
            return "[Attachment: \(name)\(source)]\n\(text)\(cut)\n[End of attachment]"
        }
        switch attachment.kind {
        case .image: return "[Image: \(name). This model cannot see images and no text was found in it.]"
        case .pdf: return "[PDF: \(name). No text could be read from it.]"
        case .text: return "[File: \(name). It is empty.]"
        case .audio: return "[Audio: \(name). Audio is not transcribed.]"
        }
    }
}
