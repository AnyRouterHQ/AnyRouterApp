import Foundation

/// "Remember that …" in the user's own message (agent design 2.3): a pass over the text, no model call. The cue is
/// dropped where it only asks ("Remember that I'm vegetarian" saves "I'm vegetarian") and kept where it is the fact
/// ("My name is Lan."). Explicit asks save even with automatic saving off; the other cues are automatic saves.
enum RememberLogic {
    struct Candidate: Equatable, Sendable {
        let text: String
        let kind: MemoryKind
        /// The user asked to remember it.
        let explicit: Bool
    }

    private struct Cue {
        let phrase: String
        let kind: MemoryKind
        let keepsCue: Bool
        let explicit: Bool
    }

    /// Longer phrases first, so "hãy nhớ rằng" is not read as "hãy nhớ" followed by "rằng".
    private static let cues: [Cue] = [
        Cue(phrase: "please remember that", kind: .fact, keepsCue: false, explicit: true),
        Cue(phrase: "remember that", kind: .fact, keepsCue: false, explicit: true),
        Cue(phrase: "hãy nhớ rằng", kind: .fact, keepsCue: false, explicit: true),
        Cue(phrase: "nhớ rằng", kind: .fact, keepsCue: false, explicit: true),
        Cue(phrase: "hãy nhớ là", kind: .fact, keepsCue: false, explicit: true),
        Cue(phrase: "nhớ giúp tôi", kind: .fact, keepsCue: false, explicit: true),
        Cue(phrase: "from now on", kind: .preference, keepsCue: false, explicit: false),
        Cue(phrase: "từ giờ trở đi", kind: .preference, keepsCue: false, explicit: false),
        Cue(phrase: "từ giờ", kind: .preference, keepsCue: false, explicit: false),
        Cue(phrase: "từ nay", kind: .preference, keepsCue: false, explicit: false),
        Cue(phrase: "my name is", kind: .profile, keepsCue: true, explicit: false),
        Cue(phrase: "tên tôi là", kind: .profile, keepsCue: true, explicit: false),
        Cue(phrase: "tôi tên là", kind: .profile, keepsCue: true, explicit: false),
        Cue(phrase: "i'm allergic to", kind: .profile, keepsCue: true, explicit: false),
        Cue(phrase: "i\u{2019}m allergic to", kind: .profile, keepsCue: true, explicit: false),
        Cue(phrase: "i am allergic to", kind: .profile, keepsCue: true, explicit: false),
        Cue(phrase: "tôi bị dị ứng", kind: .profile, keepsCue: true, explicit: false),
        Cue(phrase: "tôi dị ứng", kind: .profile, keepsCue: true, explicit: false),
    ]

    private static let sentenceEnds: Set<Character> = [".", "!", "?", "\n"]

    /// Words that may come before an ask in its sentence ("Please remember that", "Bạn hãy nhớ rằng"), without tone marks.
    /// Any other word there makes it a statement about the past ("I remember that day"), not an ask.
    private static let leadWords: Set<String> = ["please", "ok", "okay", "also", "and", "so", "hey", "oh", "lam", "on", "hay", "ban", "a", "nhe", "oi"]

    /// The first statement in the message worth saving, or nil. A question ("Do you remember that film?") is not one.
    static func candidate(in message: String) -> Candidate? {
        for cue in cues {
            guard let range = wordRange(of: cue.phrase, in: message) else { continue }
            let sentenceStart = message[..<range.lowerBound].lastIndex { sentenceEnds.contains($0) }.map { message.index(after: $0) } ?? message.startIndex
            if !cue.keepsCue, !onlyLeadWords(message[sentenceStart..<range.lowerBound]) { continue }
            let end = message[range.upperBound...].firstIndex { sentenceEnds.contains($0) } ?? message.endIndex
            if end < message.endIndex, message[end] == "?" { continue }
            let stop = end < message.endIndex && message[end] != "\n" ? message.index(after: end) : end
            let start = cue.keepsCue ? range.lowerBound : range.upperBound
            let text = String(message[start..<stop]).trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ",:;-")))
            guard text.contains(where: \.isLetter), text.count <= MemoryKind.fact.textLimit else { continue }
            let kind = cue.kind == .fact && isAboutTheUser(text) ? MemoryKind.profile : cue.kind
            return Candidate(text: text.prefix(1).uppercased() + text.dropFirst(), kind: kind, explicit: cue.explicit)
        }
        return nil
    }

    /// "I'm vegetarian", "Tôi ăn chay": who the user is, so it goes in every chat's profile (About you), not only in recall.
    private static func isAboutTheUser(_ text: String) -> Bool {
        let first = text.split { !$0.isLetter }.first?.lowercased()
        return first == "i" || first == "tôi" || first == "mình"
    }

    private static func onlyLeadWords(_ text: Substring) -> Bool {
        text.split { !$0.isLetter }.allSatisfy { leadWords.contains($0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)) }
    }

    /// The phrase as whole words, ignoring case. Tone marks count: "từ nay" (from now on) is not "từ này" (this word).
    private static func wordRange(of phrase: String, in text: String) -> Range<String.Index>? {
        var from = text.startIndex
        while let range = text.range(of: phrase, options: .caseInsensitive, range: from..<text.endIndex) {
            let before = range.lowerBound == text.startIndex || !text[text.index(before: range.lowerBound)].isLetter
            let after = range.upperBound == text.endIndex || !text[range.upperBound].isLetter
            if before && after { return range }
            from = range.upperBound
        }
        return nil
    }

    /// The row's words for each outcome.
    static func title(of outcome: MemoryUpdate.Outcome) -> String {
        switch outcome {
        case .saved: String(localized: "Memory updated")
        case .alreadySaved: String(localized: "Already in memory")
        case .refused: String(localized: "Memory not saved")
        case .undone: String(localized: "Memory update undone")
        }
    }
}
