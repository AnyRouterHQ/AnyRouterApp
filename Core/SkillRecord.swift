import Foundation
import SwiftData

/// Where a stored skill came from. A bundled skill is never stored, so it has no case here.
enum StoredSkillSource: String, Codable, CaseIterable, Sendable {
    case hub, imported, proposed

    var skillSource: Skill.Source {
        switch self {
        case .hub: .hub
        case .imported: .imported
        case .proposed: .proposed
        }
    }
}

/// One skill the user owns, kept on this device in the same store as the chats; nothing syncs from here. The text is
/// data for a cloud model to read, never instructions the app obeys (agent design 4.2, unit K2).
@Model final class SkillRecord {
    @Attribute(.unique) var id: UUID
    /// Kebab-case and not a bundled name; `SkillStore` enforces both. Not unique here: a duplicate is refused in the store.
    var name: String
    /// One line, at most 300 characters. Not called `description`: Core Data reserves that name.
    var summary: String
    /// At most 8,000 characters.
    var body: String
    var sourceRaw: String
    /// The URL a skill was imported from, or `<hub slug>/<item slug>` for a hub skill. Nil for a proposed one.
    var sourceRef: String?
    var enabled: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(), name: String, summary: String, body: String, source: StoredSkillSource,
        sourceRef: String? = nil, enabled: Bool = true, now: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.body = body
        self.sourceRaw = source.rawValue
        self.sourceRef = sourceRef
        self.enabled = enabled
        self.createdAt = now
        self.updatedAt = now
    }

    /// An unknown raw value reads as imported, the origin that claims nothing about a hub or the model.
    var source: StoredSkillSource {
        get { StoredSkillSource(rawValue: sourceRaw) ?? .imported }
        set { sourceRaw = newValue.rawValue }
    }

    var skill: Skill { Skill(name: name, description: summary, body: body, source: source.skillSource) }
}
