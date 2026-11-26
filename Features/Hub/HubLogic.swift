import Foundation

enum HubLogic {
    struct Sections: Equatable {
        var installed: [LocalModelEntry]
        var available: [LocalModelEntry]
        var isEmpty: Bool { installed.isEmpty && available.isEmpty }
    }

    /// Installed models first, the rest below; both filtered by the query (title, summary, tags).
    /// Downloads in flight stay in the available list so their progress shows where the Download button was.
    static func sections(catalog: [LocalModelEntry], state: (String) -> DownloadState, query: String) -> Sections {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matched = needle.isEmpty ? catalog : catalog.filter { matches($0, needle) }
        return Sections(
            installed: matched.filter { state($0.id) == .installed },
            available: matched.filter { state($0.id) != .installed }
        )
    }

    static func matches(_ entry: LocalModelEntry, _ needle: String) -> Bool {
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return entry.descriptor.displayName.range(of: needle, options: options) != nil
            || entry.summary.range(of: needle, options: options) != nil
            || entry.tags.contains { $0.range(of: needle, options: options) != nil }
    }

    static func percent(_ progress: Double?) -> String {
        guard let progress else { return "…" }
        return "\(Int((min(max(progress, 0), 1) * 100).rounded()))%"
    }

    static func sizeText(_ bytes: Int64?) -> String? {
        bytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
    }
}
