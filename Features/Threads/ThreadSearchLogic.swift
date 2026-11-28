import Foundation

/// Pure search for the full-screen chat search: every chat, newest first, when the query is blank, otherwise threads
/// whose title or any message contains it, with the text around the first message match.
/// Matching ignores case and diacritics, so "du lich" finds "Du lịch" and "da nang" finds "Đà Nẵng".
enum ThreadSearchLogic {
    struct Hit: Identifiable {
        let thread: ThreadRecord
        /// Text around the first message match. nil when the query matched only the title, or is blank.
        let snippet: String?
        var id: UUID { thread.id }
    }

    /// Characters kept on each side of a match.
    static let snippetRadius = 40

    /// Blank query: every chat that is not archived, newest first, so "View all" in the sidebar shows the whole list.
    /// Otherwise every such chat that matches, newest first.
    static func results(in threads: [ThreadRecord], query: String) -> [Hit] {
        let needle = fold(query.trimmingCharacters(in: .whitespacesAndNewlines))
        let newestFirst = threads.filter { !$0.isArchived }.sorted { $0.updatedAt > $1.updatedAt }
        if needle.isEmpty {
            return newestFirst.map { Hit(thread: $0, snippet: nil) }
        }
        return newestFirst.compactMap { thread in
            let found = thread.messages.sorted { $0.createdAt < $1.createdAt }
                .lazy.compactMap { snippet(in: $0.content, foldedNeedle: needle) }.first
            guard found != nil || fold(thread.title).contains(needle) else { return nil }
            return Hit(thread: thread, snippet: found)
        }
    }

    /// Lowercased with marks removed. The stroke d of Vietnamese has no decomposition, and sharp s is two letters, so both are mapped by hand.
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: "đ", with: "d")
            .replacingOccurrences(of: "Đ", with: "d")
            .replacingOccurrences(of: "ß", with: "ss")
    }

    /// The match with 40 characters around it, on one line, with an ellipsis where it was cut.
    static func snippet(in text: String, foldedNeedle needle: String) -> String? {
        let folded = fold(text)
        guard let match = folded.range(of: needle) else { return nil }
        // Offsets carry over to the original only while folding kept one character per character.
        guard folded.count == text.count else { return oneLine(text.prefix(snippetRadius * 2)) }
        let start = folded.distance(from: folded.startIndex, to: match.lowerBound)
        let end = folded.distance(from: folded.startIndex, to: match.upperBound)
        let from = max(0, start - snippetRadius)
        let to = min(text.count, end + snippetRadius)
        let slice = text[text.index(text.startIndex, offsetBy: from)..<text.index(text.startIndex, offsetBy: to)]
        return (from > 0 ? "…" : "") + oneLine(slice) + (to < text.count ? "…" : "")
    }

    private static func oneLine(_ text: some StringProtocol) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
