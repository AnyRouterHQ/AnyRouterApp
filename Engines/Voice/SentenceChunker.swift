import Foundation

/// Cuts a reply that arrives in pieces into sentences a speech engine can start on early.
/// Feed it text with `push`; call `finish` at the end. It knows English and Vietnamese punctuation (the same Latin marks),
/// the CJK full stops, common abbreviations ("TP. Hồ Chí Minh", "Dr. Lee"), decimals ("3.14") and list lines.
struct SentenceChunker: Sendable {
    /// A sentence shorter than this waits for the next one, so speech is not chopped into one-word clips.
    /// The first sentence of a reply is exempt: speech should start as soon as there is something to say.
    var minimumLength = 24
    /// A run with no sentence end is cut at a comma or space once it is this long.
    var maximumLength = 220

    private var raw = ""
    private var consumed = 0
    private var hasEmitted = false

    private static let terminators: Set<Character> = [".", "!", "?", "\u{2026}", "\u{3002}", "\u{FF01}", "\u{FF1F}"]
    private static let fullWidth: Set<Character> = ["\u{3002}", "\u{FF01}", "\u{FF1F}"]
    private static let closers: Set<Character> = ["\"", "'", ")", "]", "\u{201D}", "\u{2019}", "\u{00BB}"]
    private static let punctuation: Set<Character> = [".", "!", "?", "\u{2026}", ":", ";", ",", "\u{3002}", "\u{FF01}", "\u{FF1F}"]
    private static let abbreviations: Set<String> = [
        "mr", "mrs", "ms", "dr", "prof", "sr", "jr", "st", "vs", "etc", "e.g", "i.e", "approx", "inc", "ltd",
        "tp", "gs", "ts", "pgs", "ths", "th.s",
    ]

    init(minimumLength: Int = 24, maximumLength: Int = 220) {
        self.minimumLength = minimumLength
        self.maximumLength = maximumLength
    }

    mutating func push(_ text: String) -> [String] {
        raw += text
        return drain(final: false)
    }

    /// The rest of the reply, as one last sentence.
    mutating func finish() -> [String] {
        drain(final: true)
    }

    private mutating func drain(final: Bool) -> [String] {
        let chars = Array(SpeechText.clean(raw))
        var start = min(consumed, chars.count)
        var output: [String] = []
        var index = start
        while index < chars.count {
            let end = Self.boundary(in: chars, at: index, final: final)
            if let end {
                let piece = Self.normalized(chars[start..<end])
                if !Self.isSpeakable(piece) {
                    start = end
                    consumed = end
                } else if !hasEmitted || piece.count >= minimumLength {
                    output.append(piece)
                    hasEmitted = true
                    start = end
                    consumed = end
                }
                index = end
            } else {
                index += 1
            }
        }
        if final {
            let rest = Self.normalized(chars[start...])
            if Self.isSpeakable(rest) {
                output.append(rest)
                hasEmitted = true
            }
            consumed = chars.count
        } else if let cut = Self.longRunCut(chars, from: start, limit: maximumLength) {
            output.append(Self.normalized(chars[start..<cut]))
            hasEmitted = true
            consumed = cut
        }
        return output
    }

    /// The index just past a sentence end at `index`, or nil when none ends there.
    private static func boundary(in chars: [Character], at index: Int, final: Bool) -> Int? {
        let c = chars[index]
        if c == "\n" { return index + 1 }
        guard terminators.contains(c) else { return nil }
        var next = index + 1
        while next < chars.count, terminators.contains(chars[next]) || closers.contains(chars[next]) { next += 1 }
        if fullWidth.contains(c) { return next }
        if next >= chars.count {
            // A stop at the very end of the text so far may be the start of "3.14": wait for the next character.
            return final && !endsAbbreviation(chars, at: index) ? next : nil
        }
        guard chars[next].isWhitespace, !endsAbbreviation(chars, at: index) else { return nil }
        return next
    }

    /// True for "Dr." and "TP." and for a lone initial such as "J.".
    private static func endsAbbreviation(_ chars: [Character], at index: Int) -> Bool {
        guard chars[index] == "." else { return false }
        var begin = index
        while begin > 0, chars[begin - 1].isLetter || chars[begin - 1] == "." { begin -= 1 }
        let word = String(chars[begin..<index])
        if abbreviations.contains(word.lowercased()) { return true }
        return word.count == 1 && word.first?.isUppercase == true
    }

    private static func normalized(_ slice: ArraySlice<Character>) -> String {
        let lines = String(slice).split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return lines.map { line in
            guard let last = line.last, !punctuation.contains(last) else { return line }
            return line + "."
        }
        .joined(separator: " ")
    }

    private static func isSpeakable(_ text: String) -> Bool {
        text.contains { $0.isLetter || $0.isNumber }
    }

    /// Where to cut a run that has gone `limit` characters without a sentence end: after the last comma, semicolon or colon
    /// past a quarter of the limit, else after the last space.
    private static func longRunCut(_ chars: [Character], from start: Int, limit: Int) -> Int? {
        guard chars.count - start > limit else { return nil }
        let window = start..<(start + limit)
        let floor = start + limit / 4
        if let comma = window.last(where: { $0 >= floor && [",", ";", ":"].contains(chars[$0]) }) { return comma + 1 }
        if let space = window.last(where: { chars[$0] == " " }) { return space + 1 }
        return start + limit
    }
}
