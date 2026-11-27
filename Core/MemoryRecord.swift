import Foundation
import SwiftData

/// What a memory is about. The Memory page shows the kinds in `MemoryKind.pageOrder`.
enum MemoryKind: String, Codable, CaseIterable, Sendable {
    case profile, preference, fact, note, chatSummary
}

/// How a memory got here.
enum MemoryOrigin: String, Codable, CaseIterable, Sendable {
    case typedInSettings, askedInChat, extracted, modelTool
}

/// Where the content came from, which decides where it may go: `deviceOnly` came from a chat with a model that runs
/// on this device and stays off cloud models unless the user allows it.
enum MemoryScope: String, Codable, CaseIterable, Sendable {
    case everywhere, deviceOnly
}

/// One write to memory as the reply shows it: a "Memory updated" row with Undo and Edit (agent design 2.3).
struct MemoryUpdate: Codable, Equatable, Sendable, Identifiable {
    enum Outcome: Codable, Equatable, Sendable {
        case saved
        case alreadySaved
        /// Not saved; the words say why (too long, the list is full).
        case refused(String)
        /// The model removed the item; Undo saves it again with its old kind and scope.
        case removed
        case undone
    }

    var id: UUID
    /// The saved item, while it exists.
    var memoryID: UUID?
    var text: String
    var outcome: Outcome
    /// A removed item's kind and scope, so Undo can save it again as it was.
    var kind: MemoryKind?
    var scope: MemoryScope?

    init(id: UUID = UUID(), memoryID: UUID? = nil, text: String, outcome: Outcome, kind: MemoryKind? = nil, scope: MemoryScope? = nil) {
        self.id = id
        self.memoryID = memoryID
        self.text = text
        self.outcome = outcome
        self.kind = kind
        self.scope = scope
    }
}

/// A memory put in front of a question (agent design 2.4). The reply's footer lists it with Forget.
struct MemoryHit: Codable, Equatable, Sendable, Identifiable {
    var memoryID: UUID
    var text: String
    var id: UUID { memoryID }
}

/// One short thing the app remembers about the user. Lives in the same store as the chats; nothing syncs.
@Model final class MemoryRecord {
    @Attribute(.unique) var id: UUID
    var kindRaw: String
    /// One short statement, at most 280 characters; a chat summary at most 600 (`MemoryStore` enforces it).
    var text: String
    var originRaw: String
    var scopeRaw: String
    var sourceThreadID: UUID?
    var sourceMessageID: UUID?
    var createdAt: Date
    var updatedAt: Date
    var lastUsedAt: Date?
    var useCount: Int = 0
    /// Later, only with consent. Nil until then.
    var embedding: Data?
    var embeddingModel: String?

    init(
        id: UUID = UUID(), kind: MemoryKind, text: String, origin: MemoryOrigin, scope: MemoryScope,
        sourceThreadID: UUID? = nil, sourceMessageID: UUID? = nil, now: Date = Date()
    ) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.text = text
        self.originRaw = origin.rawValue
        self.scopeRaw = scope.rawValue
        self.sourceThreadID = sourceThreadID
        self.sourceMessageID = sourceMessageID
        self.createdAt = now
        self.updatedAt = now
    }

    /// An unknown raw value reads as a note: the one kind that is always safe to show and keep.
    var kind: MemoryKind {
        get { MemoryKind(rawValue: kindRaw) ?? .note }
        set { kindRaw = newValue.rawValue }
    }

    /// An unknown raw value reads as typed in Settings, the origin that claims nothing about a chat.
    var origin: MemoryOrigin {
        get { MemoryOrigin(rawValue: originRaw) ?? .typedInSettings }
        set { originRaw = newValue.rawValue }
    }

    /// An unknown raw value reads as `deviceOnly`, the scope that keeps the item off cloud models.
    var scope: MemoryScope {
        get { MemoryScope(rawValue: scopeRaw) ?? .deviceOnly }
        set { scopeRaw = newValue.rawValue }
    }

    /// The last time the item was used, or when it was saved.
    var lastTouched: Date { lastUsedAt ?? createdAt }
}
