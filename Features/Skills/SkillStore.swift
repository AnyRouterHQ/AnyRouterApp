import Foundation
import SwiftData

enum SkillStoreError: Error, Equatable, LocalizedError {
    case duplicate(String)
    case full(Int)

    var errorDescription: String? {
        switch self {
        case .duplicate(let name): "You already have a skill named \(name)."
        case .full(let limit): "You have \(limit) skills, the most the app keeps. Delete one to make room."
        }
    }
}

/// Reads and writes the skills the user owns. Every write is checked here, so Settings, imports, the hub and the model's
/// proposals share one set of rules.
@MainActor
struct SkillStore {
    static let limit = 100

    let context: ModelContext

    /// Saves a new skill, switched on. The text is checked by `SkillLibraryLogic.validate` first.
    @discardableResult
    func add(
        _ draft: SkillDraft, source: StoredSkillSource, sourceRef: String? = nil, now: Date = Date()
    ) throws -> SkillRecord {
        let clean = try SkillLibraryLogic.validate(draft)
        let stored = try all()
        guard !stored.contains(where: { $0.name == clean.name }) else { throw SkillStoreError.duplicate(clean.name) }
        guard stored.count < Self.limit else { throw SkillStoreError.full(Self.limit) }
        let record = SkillRecord(
            name: clean.name, summary: clean.description, body: clean.body, source: source, sourceRef: sourceRef, now: now)
        context.insert(record)
        try context.save()
        return record
    }

    func setEnabled(_ record: SkillRecord, _ enabled: Bool, now: Date = Date()) throws {
        record.enabled = enabled
        record.updatedAt = now
        try context.save()
    }

    func delete(_ record: SkillRecord) throws {
        context.delete(record)
        try context.save()
    }

    /// Every stored skill, by name.
    func all() throws -> [SkillRecord] {
        try context.fetch(FetchDescriptor<SkillRecord>(sortBy: [SortDescriptor(\.name)]))
    }

    /// The stored skills that are switched on, as a chat offers them.
    func enabledSkills() throws -> [Skill] {
        try all().filter(\.enabled).map(\.skill)
    }
}
