import Foundation
import SwiftData

/// A limit shared by some kinds. A write past it is refused; nothing is removed by itself.
struct MemoryCap: Equatable, Sendable {
    let kinds: [MemoryKind]
    let limit: Int
    let name: String
}

extension MemoryKind {
    /// The order the Memory page shows its groups.
    static let pageOrder: [MemoryKind] = [.profile, .preference, .note, .fact, .chatSummary]
    /// The kinds the Add menu offers. Chat summaries are written by the app.
    static let addable: [MemoryKind] = [.profile, .preference, .note, .fact]

    var groupTitle: String {
        switch self {
        case .profile: "About you"
        case .preference: "Preferences"
        case .note: "Pinned notes"
        case .fact: "Facts"
        case .chatSummary: "Chat summaries"
        }
    }

    var addTitle: String {
        switch self {
        case .profile: "About you"
        case .preference: "Preference"
        case .note: "Note"
        case .fact: "Fact"
        case .chatSummary: "Chat summary"
        }
    }

    /// Most characters one item may have.
    var textLimit: Int { self == .chatSummary ? 600 : 280 }

    /// 60 items of About you, Preferences and Pinned notes together, 500 facts, no cap on chat summaries.
    var cap: MemoryCap? {
        switch self {
        case .profile, .preference, .note:
            MemoryCap(kinds: [.profile, .preference, .note], limit: 60, name: "About you, Preferences and Pinned notes")
        case .fact:
            MemoryCap(kinds: [.fact], limit: 500, name: "Facts")
        case .chatSummary:
            nil
        }
    }
}

extension MemoryOrigin {
    var label: String {
        switch self {
        case .typedInSettings: "Typed in Settings"
        case .askedInChat: "You asked in a chat"
        case .extracted: "Saved from a chat"
        case .modelTool: "Saved by the model"
        }
    }
}

enum MemoryError: Error, Equatable, LocalizedError {
    case empty
    case tooLong(limit: Int)
    case duplicate
    /// `oldestUnused` are short excerpts of the items the user may want to delete first.
    case full(name: String, limit: Int, oldestUnused: [String])

    var errorDescription: String? {
        switch self {
        case .empty:
            "Write something to remember."
        case .tooLong(let limit):
            "That is too long. Keep it to \(limit) characters or fewer."
        case .duplicate:
            "You already have that in memory."
        case .full(let name, let limit, let oldest):
            "\(name) is full (\(limit) items). Delete one to make room. Oldest unused: "
                + oldest.map { "\u{201C}\($0)\u{201D}" }.joined(separator: ", ") + "."
        }
    }
}

/// The items of one kind, as the page shows them.
struct MemoryGroup: Identifiable {
    let kind: MemoryKind
    let records: [MemoryRecord]
    var id: MemoryKind { kind }
}

/// Reads and writes the user's memory. Every write is checked here, so Settings, the chat and the model tools share
/// one set of rules.
@MainActor
struct MemoryStore {
    let context: ModelContext

    /// Saves a new item. Typed in Settings is `everywhere`: the page says it goes to the model you chat with.
    @discardableResult
    func add(
        _ text: String, kind: MemoryKind, origin: MemoryOrigin = .typedInSettings, scope: MemoryScope = .everywhere,
        sourceThreadID: UUID? = nil, sourceMessageID: UUID? = nil, now: Date = Date()
    ) throws -> MemoryRecord {
        let clean = try Self.validated(text, kind: kind)
        let all = try all()
        guard !Self.isDuplicate(clean, in: all) else { throw MemoryError.duplicate }
        if let cap = kind.cap {
            let group = all.filter { cap.kinds.contains($0.kind) }
            if group.count >= cap.limit {
                throw MemoryError.full(name: cap.name, limit: cap.limit, oldestUnused: Self.oldestUnused(group))
            }
        }
        let record = MemoryRecord(
            kind: kind, text: clean, origin: origin, scope: scope,
            sourceThreadID: sourceThreadID, sourceMessageID: sourceMessageID, now: now)
        context.insert(record)
        try context.save()
        return record
    }

    func edit(_ record: MemoryRecord, text: String, now: Date = Date()) throws {
        let clean = try Self.validated(text, kind: record.kind)
        let others = try all().filter { $0.id != record.id }
        guard !Self.isDuplicate(clean, in: others) else { throw MemoryError.duplicate }
        record.text = clean
        record.updatedAt = now
        try context.save()
    }

    func delete(_ record: MemoryRecord) throws {
        context.delete(record)
        try context.save()
    }

    func deleteAll() throws {
        for record in try all() { context.delete(record) }
        try context.save()
    }

    func all() throws -> [MemoryRecord] {
        try context.fetch(FetchDescriptor<MemoryRecord>(sortBy: [SortDescriptor(\.createdAt)]))
    }

    func list() throws -> [MemoryGroup] { Self.groups(try all()) }

    /// Groups in page order, newest edit first inside a group. Empty groups are left out.
    static func groups(_ records: [MemoryRecord]) -> [MemoryGroup] {
        MemoryKind.pageOrder.compactMap { kind in
            let items = records.filter { $0.kind == kind }.sorted { $0.updatedAt > $1.updatedAt }
            return items.isEmpty ? nil : MemoryGroup(kind: kind, records: items)
        }
    }

    /// "From the chat Trip to Da Lat" when the chat is known, else how the item was saved.
    static func sourceText(of record: MemoryRecord, threadTitle: String?) -> String {
        if record.sourceThreadID != nil, let threadTitle { return "From the chat \(threadTitle)" }
        return record.origin.label
    }

    private static func validated(_ text: String, kind: MemoryKind) throws -> String {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw MemoryError.empty }
        guard clean.count <= kind.textLimit else { throw MemoryError.tooLong(limit: kind.textLimit) }
        return clean
    }

    /// Case and diacritics do not make a new memory: "Tôi ăn chay" and "toi an chay" are the same item.
    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    private static func isDuplicate(_ text: String, in records: [MemoryRecord]) -> Bool {
        let folded = fold(text)
        return records.contains { fold($0.text) == folded }
    }

    /// Items never used first, then the ones used longest ago.
    private static func oldestUnused(_ records: [MemoryRecord]) -> [String] {
        func key(_ record: MemoryRecord) -> (Int, Date) { (record.useCount > 0 ? 1 : 0, record.lastTouched) }
        return records.sorted { key($0) < key($1) }.prefix(3).map(excerpt)
    }

    private static func excerpt(_ record: MemoryRecord) -> String {
        record.text.count > 40 ? String(record.text.prefix(40)) + "\u{2026}" : record.text
    }
}
