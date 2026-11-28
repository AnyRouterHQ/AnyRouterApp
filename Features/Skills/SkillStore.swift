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

/// What a hub sync changed. `skipped` counts items whose text broke the rules or whose name a skill of the user's already has.
struct SkillSyncReport: Equatable, Sendable {
    var added = 0
    var updated = 0
    var removed = 0
    var skipped = 0

    /// For the page: only the counts that are not zero.
    var summary: String {
        let parts = [("added", added), ("updated", updated), ("removed", removed), ("skipped", skipped)]
            .filter { $0.1 > 0 }.map { "\($0.1) \($0.0)" }
        return parts.isEmpty ? "Nothing changed." : parts.joined(separator: ", ") + "."
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

    /// Makes the stored hub skills match `items`: new ones are added, changed ones are updated (the switch stays as the user
    /// set it) and hub skills that are no longer in the hub, or no longer pass the rules, are deleted. Skills the user
    /// imported or approved are never touched, and one of them keeps its name against a hub skill of the same name.
    @discardableResult
    func sync(_ items: [HubSkillItem], now: Date = Date()) throws -> SkillSyncReport {
        var report = SkillSyncReport()
        var accepted: [(item: HubSkillItem, draft: SkillDraft)] = []
        for item in items {
            if let draft = try? SkillLibraryLogic.hubDraft(slug: item.slug, description: item.description, body: item.body) {
                accepted.append((item, draft))
            } else {
                report.skipped += 1
            }
        }
        let wanted = Set(accepted.map { $0.item.ref })
        for record in try all() where record.source == .hub {
            // A hub record with no reference cannot match an item, so it goes too.
            if record.sourceRef.map({ wanted.contains($0) }) == true { continue }
            context.delete(record)
            report.removed += 1
        }
        try context.save()
        var stored = try all()
        for (item, draft) in accepted {
            if let existing = stored.first(where: { $0.source == .hub && $0.sourceRef == item.ref }) {
                guard existing.summary != draft.description || existing.body != draft.body else { continue }
                existing.summary = draft.description
                existing.body = draft.body
                existing.updatedAt = now
                report.updated += 1
            } else if stored.contains(where: { $0.name == draft.name }) || stored.count >= Self.limit {
                report.skipped += 1
            } else {
                let record = SkillRecord(
                    name: draft.name, summary: draft.description, body: draft.body, source: .hub, sourceRef: item.ref, now: now)
                context.insert(record)
                stored.append(record)
                report.added += 1
            }
        }
        try context.save()
        return report
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
