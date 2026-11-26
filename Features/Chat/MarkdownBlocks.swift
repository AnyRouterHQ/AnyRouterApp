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

    enum Kind: Equatable { case heading, code, list, other }

    /// What a block is, from its first line: a heading, a fenced code block, a list, or anything else.
    static func kind(of block: String) -> Kind {
        let first = block.prefix(while: { $0 != "\n" })
        let text = first.drop(while: { $0 == " " })
        if text.hasPrefix("#") { return .heading }
        if text.hasPrefix("```") || text.hasPrefix("~~~") { return .code }
        if isListItem(first) { return .list }
        return .other
    }

    /// The space above a block, in ems of the body text size: about 0.7 between paragraphs, a little more around
    /// lists and code, more above a heading and less below it, so a heading stays with what it introduces.
    /// Lists keep their own tight spacing inside; this is only the space between blocks.
    static func gap(before block: String, after previous: String) -> Double {
        let (above, below) = (kind(of: previous), kind(of: block))
        if above == .heading { return 0.4 }
        if below == .heading { return 1.1 }
        if above == .code || above == .list || below == .code || below == .list { return 0.9 }
        return 0.7
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
