import Foundation

/// Splits a markdown reply into blocks at blank lines outside code fences, so a streaming reply
/// re-parses and re-lays out only its last block. A block that has a following block never changes again.
/// Kept together on purpose: an indented line after a blank line (a list item's second paragraph) and
/// consecutive list items.
enum MarkdownBlocks {
    static func split(_ text: String) -> [String] {
        var blocks: [String] = []
        var current: [Substring] = []
        var blanks: [Substring] = []
        var fence: Character?
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if fence == nil, line.allSatisfy(\.isWhitespace) {
                blanks.append(line)
                continue
            }
            if !blanks.isEmpty {
                if current.isEmpty {
                    // Leading blank lines carry no meaning.
                } else if startsNewBlock(line, after: current[0]) {
                    blocks.append(current.joined(separator: "\n"))
                    current = []
                } else {
                    current.append(contentsOf: blanks)
                }
                blanks = []
            }
            current.append(line)
            if let marker = fenceMarker(line) {
                if fence == nil { fence = marker } else if fence == marker { fence = nil }
            }
        }
        if !current.isEmpty { blocks.append(current.joined(separator: "\n")) }
        return blocks
    }

    private static func startsNewBlock(_ line: Substring, after first: Substring) -> Bool {
        if line.first?.isWhitespace == true { return false }
        return !(isListItem(line) && isListItem(first))
    }

    private static func isListItem(_ line: Substring) -> Bool {
        // A marker alone ("-" or "2.") counts: a streaming reply shows it before the space and the text arrive.
        let text = line.drop(while: { $0 == " " })
        if ["-", "*", "+"].contains(where: { text == $0 || text.hasPrefix($0 + " ") }) { return true }
        let digits = text.prefix(while: \.isNumber)
        guard !digits.isEmpty else { return false }
        let rest = text.dropFirst(digits.count)
        return [".", ")"].contains(where: { rest == $0 || rest.hasPrefix($0 + " ") })
    }

    private static func fenceMarker(_ line: Substring) -> Character? {
        let text = line.drop(while: { $0 == " " })
        guard let first = text.first, first == "`" || first == "~" else { return nil }
        return text.prefix(3).count == 3 && text.prefix(3).allSatisfy({ $0 == first }) ? first : nil
    }
}
