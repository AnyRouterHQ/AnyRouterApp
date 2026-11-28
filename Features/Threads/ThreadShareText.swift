import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// A chat as text for the share sheet: the title, then each turn under "You:" or the model's name. Tool steps,
/// reasoning and failed empty replies are not part of it.
enum ThreadShareText {
    static let assistantFallbackName = "Assistant"

    static func text(for thread: ThreadRecord) -> String {
        var parts = ["# " + thread.title]
        for message in thread.messages.sorted(by: { $0.createdAt < $1.createdAt }) where message.role != .system {
            let body = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { continue }
            let name = message.role == .user ? "You" : speaker(message.modelName)
            parts.append("\(name):\n\(body)")
        }
        return parts.joined(separator: "\n\n") + "\n"
    }

    private static func speaker(_ modelName: String?) -> String {
        guard let name = modelName?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return assistantFallbackName }
        return name
    }

    /// The title cut down to letters, digits and dashes, so it is safe as a file name.
    static func fileName(for title: String) -> String {
        let words = String(title.map { $0.isLetter || $0.isNumber ? $0 : " " })
            .split(whereSeparator: \.isWhitespace)
        let stem = String(words.joined(separator: "-").prefix(60))
        return (stem.isEmpty ? "Chat" : stem) + ".md"
    }

    /// Writes the text to a fresh temporary folder under the title's file name and returns the file.
    static func writeFile(title: String, text: String, in root: URL = FileManager.default.temporaryDirectory) throws -> URL {
        let folder = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(fileName(for: title))
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

/// What a share sheet receives: a file named after the chat, or the plain text where a file does not fit.
struct ThreadShareItem: Transferable {
    let title: String
    let text: String

    init(_ thread: ThreadRecord) {
        title = thread.title
        text = ThreadShareText.text(for: thread)
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .plainText) { item in
            SentTransferredFile(try ThreadShareText.writeFile(title: item.title, text: item.text))
        }
        ProxyRepresentation { $0.text }
    }
}
