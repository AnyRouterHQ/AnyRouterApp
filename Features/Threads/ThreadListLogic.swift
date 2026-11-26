import Foundation

/// Pure filtering and grouping for the thread sidebar.
enum ThreadListLogic {
    struct Sections {
        var pinned: [ThreadRecord]
        var recent: [ThreadRecord]
        var isEmpty: Bool { pinned.isEmpty && recent.isEmpty }
    }

    /// Pinned threads first, each group newest first. A non-empty query keeps threads whose title
    /// or any message contains it (case and diacritic insensitive).
    static func sections(from threads: [ThreadRecord], query: String) -> Sections {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matched = needle.isEmpty ? threads : threads.filter { matches($0, needle) }
        let sorted = matched.sorted { $0.updatedAt > $1.updatedAt }
        return Sections(pinned: sorted.filter(\.isPinned), recent: sorted.filter { !$0.isPinned })
    }

    static func matches(_ thread: ThreadRecord, _ needle: String) -> Bool {
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        if thread.title.range(of: needle, options: options) != nil { return true }
        return thread.messages.contains { $0.content.range(of: needle, options: options) != nil }
    }

    /// Title for a thread created from its first user message.
    static func title(fromFirstMessage text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "New chat" }
        return trimmed.count > 48 ? String(trimmed.prefix(48)) + "…" : trimmed
    }

    /// Rename result: an empty name keeps the old title.
    static func renamed(_ proposed: String, current: String) -> String {
        let trimmed = proposed.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? current : trimmed
    }
}
