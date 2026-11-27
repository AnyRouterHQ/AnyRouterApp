import Foundation

/// What one on-device pass read in an image: its text in reading order, and each table as rows of cell text.
/// The `ocr_image` tool and the Extract screen read images through the same reader.
struct ImageText: Equatable, Sendable {
    var text: String
    var tables: [[[String]]] = []

    var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && tables.isEmpty }

    /// The text, then each table as Markdown rows with the first row as its header.
    var rendered: String {
        var parts: [String] = []
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !body.isEmpty { parts.append(body) }
        for (index, table) in tables.enumerated() where !table.isEmpty {
            let width = table.map(\.count).max() ?? 0
            let rows = table.map { row in
                let cells = row + Array(repeating: "", count: width - row.count)
                return "| " + cells.map(Self.cell).joined(separator: " | ") + " |"
            }
            let rule = "|" + String(repeating: " --- |", count: width)
            parts.append("Table \(index + 1):\n" + ([rows[0], rule] + rows.dropFirst()).joined(separator: "\n"))
        }
        return parts.joined(separator: "\n\n")
    }

    private static func cell(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).joined(separator: " ").replacingOccurrences(of: "|", with: "\\|")
    }
}

/// Reads the text in an image's bytes. Tests pass a fake; the app uses `VisionTextReader`.
protocol ImageTextReading: Sendable {
    func read(_ image: Data) async throws -> ImageText
}

/// On-device Vision text recognition, the same pass a photo gets when it is attached. Nothing leaves the device.
struct VisionTextReader: ImageTextReading {
    func read(_ image: Data) async throws -> ImageText {
        ImageText(text: TextExtraction.ocr(image) ?? "")
    }
}
