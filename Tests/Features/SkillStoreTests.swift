import Foundation
import SwiftData
import Testing
@testable import AnyRouter

@MainActor
struct SkillStoreTests {
    private func makeStore() throws -> SkillStore {
        SkillStore(context: ModelContext(try ModelContainer.anyRouter(inMemory: true)))
    }

    private func draft(_ name: String) -> SkillDraft {
        SkillDraft(name: name, description: "Does \(name).", body: "1. Do \(name).")
    }

    private func thrown(_ work: () throws -> Void) -> SkillStoreError? {
        do { try work() } catch { return error as? SkillStoreError }
        return nil
    }

    @Test func addKeepsTheCheckedTextItsSourceAndSwitchesItOn() throws {
        let store = try makeStore()
        let now = Date(timeIntervalSince1970: 100)
        let record = try store.add(
            SkillDraft(name: " bill-splitter ", description: "Split\na bill.", body: " Steps. "),
            source: .imported, sourceRef: "https://example.com/SKILL.md", now: now)
        #expect(record.name == "bill-splitter" && record.summary == "Split a bill." && record.body == "Steps.")
        #expect(record.source == .imported && record.sourceRef == "https://example.com/SKILL.md")
        #expect(record.enabled && record.createdAt == now && record.updatedAt == now)
        #expect(record.skill == Skill(name: "bill-splitter", description: "Split a bill.", body: "Steps.", source: .imported))
    }

    @Test func textThatBreaksTheRulesIsNotStored() throws {
        let store = try makeStore()
        #expect(throws: SkillIssue.badName) { try store.add(draft("Bad Name"), source: .imported) }
        #expect(throws: SkillIssue.reservedName) { try store.add(draft("email-writer"), source: .proposed) }
        #expect(try store.all().isEmpty)
    }

    @Test func aNameIsStoredOnceWhateverTheSource() throws {
        let store = try makeStore()
        try store.add(draft("bill-splitter"), source: .imported)
        #expect(thrown { try store.add(draft("bill-splitter"), source: .hub) } == .duplicate("bill-splitter"))
        #expect(try store.all().count == 1)
    }

    @Test func theStoreHoldsAtMostOneHundredSkills() throws {
        let store = try makeStore()
        for index in 0..<SkillStore.limit { try store.add(draft("skill-\(index)"), source: .hub) }
        #expect(thrown { try store.add(draft("one-more"), source: .hub) } == .full(100))
        #expect(try store.all().count == 100)
    }

    @Test func theSwitchDecidesWhichSkillsAChatOffers() throws {
        let store = try makeStore()
        let a = try store.add(draft("alpha"), source: .imported)
        try store.add(draft("beta"), source: .proposed)
        #expect(try store.enabledSkills().map(\.name) == ["alpha", "beta"], "listed by name")
        let later = Date(timeIntervalSince1970: 500)
        try store.setEnabled(a, false, now: later)
        #expect(!a.enabled && a.updatedAt == later)
        #expect(try store.enabledSkills().map(\.name) == ["beta"])
        try store.setEnabled(a, true)
        #expect(try store.enabledSkills().count == 2)
    }

    @Test func deleteRemovesTheSkill() throws {
        let store = try makeStore()
        let a = try store.add(draft("alpha"), source: .imported)
        try store.add(draft("beta"), source: .imported)
        try store.delete(a)
        #expect(try store.all().map(\.name) == ["beta"])
    }

    @Test func errorsSayWhatToDo() {
        #expect(SkillStoreError.duplicate("x").errorDescription?.contains("x") == true)
        #expect(SkillStoreError.full(100).errorDescription?.contains("100") == true)
    }

    @Test func aStoredSourceMapsToTheSkillSourceAndAnUnknownRawValueReadsAsImported() throws {
        let sources = StoredSkillSource.allCases
        #expect(sources.map(\.skillSource) == [.hub, .imported, .proposed])
        let record = SkillRecord(name: "alpha", summary: "A.", body: "x", source: .hub)
        #expect(record.source == .hub)
        record.source = .proposed
        #expect(record.sourceRaw == "proposed")
        record.sourceRaw = "bundled"
        #expect(record.source == .imported, "a bundled skill is never stored, so the raw value is not trusted")
    }
}
