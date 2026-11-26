import Foundation

/// Pure grouping and naming for the thread sidebar. Search lives in `ThreadSearchLogic`.
enum ThreadListLogic {
    struct Sections {
        var pinned: [ThreadRecord]
        var recent: [ThreadRecord]
        var isEmpty: Bool { pinned.isEmpty && recent.isEmpty }
    }

    /// Pinned threads first, each group newest first.
    static func sections(from threads: [ThreadRecord]) -> Sections {
        let sorted = threads.sorted { $0.updatedAt > $1.updatedAt }
        return Sections(pinned: sorted.filter(\.isPinned), recent: sorted.filter { !$0.isPinned })
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
