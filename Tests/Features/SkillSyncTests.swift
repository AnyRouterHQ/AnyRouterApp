import Foundation
import SwiftData
import Testing
@testable import AnyRouter

/// `SkillStore.sync`: the stored hub skills follow the hub; the user's own skills are never touched.
@MainActor
struct SkillSyncTests {
    private func makeStore() throws -> SkillStore {
        SkillStore(context: ModelContext(try ModelContainer.anyRouter(inMemory: true)))
    }

    private func item(_ slug: String, hub: String = "mine", description: String? = "Does it.", body: String = "1. Do it.") -> HubSkillItem {
        HubSkillItem(hub: hub, slug: slug, description: description, body: body)
    }

    @Test func aFirstSyncAddsEverySkillAsAHubSkillSwitchedOn() throws {
        let store = try makeStore()
        let now = Date(timeIntervalSince1970: 7)
        let report = try store.sync([item("alpha"), item("beta", hub: "team")], now: now)
        #expect(report == SkillSyncReport(added: 2, updated: 0, removed: 0, skipped: 0))
        let stored = try store.all()
        #expect(stored.map(\.name) == ["alpha", "beta"] && stored.allSatisfy { $0.source == .hub && $0.enabled && $0.createdAt == now })
        #expect(stored.map(\.sourceRef) == ["mine/alpha", "team/beta"])
        #expect(report.summary == "2 added.")
    }

    @Test func aSecondSyncOfTheSameHubChangesNothingAndKeepsTheUsersSwitch() throws {
        let store = try makeStore()
        try store.sync([item("alpha")])
        let record = try #require(try store.all().first)
        try store.setEnabled(record, false)
        let report = try store.sync([item("alpha")], now: Date(timeIntervalSince1970: 99))
        #expect(report == SkillSyncReport() && report.summary == "Nothing changed.")
        #expect(!record.enabled && record.updatedAt != Date(timeIntervalSince1970: 99))
    }

    @Test func aChangedSkillIsUpdatedInPlaceWithItsSwitchAsTheUserLeftIt() throws {
        let store = try makeStore()
        try store.sync([item("alpha")])
        let record = try #require(try store.all().first)
        try store.setEnabled(record, false)
        let later = Date(timeIntervalSince1970: 500)
        #expect(try store.sync([item("alpha", description: "New words.", body: "2. Changed.")], now: later) == SkillSyncReport(updated: 1))
        #expect(record.summary == "New words." && record.body == "2. Changed." && record.updatedAt == later && !record.enabled)
        #expect(try store.sync([item("alpha", description: "New words.", body: "3. Only the steps.")]).updated == 1)
        #expect(try store.sync([item("alpha", description: "Only the words.", body: "3. Only the steps.")]).updated == 1)
        #expect(try store.all().count == 1)
    }

    @Test func aSkillLeftOutOfTheHubIsDeletedAndOneThatNowBreaksTheRulesToo() throws {
        let store = try makeStore()
        try store.sync([item("alpha"), item("beta"), item("gamma")])
        let report = try store.sync([item("alpha"), item("beta", body: String(repeating: "x", count: 9_000))])
        #expect(report == SkillSyncReport(added: 0, updated: 0, removed: 2, skipped: 1))
        #expect(try store.all().map(\.name) == ["alpha"])
        #expect(report.summary == "2 removed, 1 skipped.")
    }

    @Test func aSyncNeverTouchesTheUsersOwnSkills() throws {
        let store = try makeStore()
        try store.add(SkillDraft(name: "mine-one", description: "Imported.", body: "1. Mine."), source: .imported, sourceRef: "https://example.com/a")
        try store.add(SkillDraft(name: "mine-two", description: "Approved.", body: "1. Mine."), source: .proposed)
        let clash = item("mine-one", description: "From the hub.", body: "1. Hub steps.")
        let report = try store.sync([clash])
        #expect(report.skipped == 1 && report.added == 0 && report.removed == 0)
        #expect(try store.sync([]).removed == 0)
        let kept = try store.all()
        #expect(kept.map(\.name) == ["mine-one", "mine-two"] && kept[0].body == "1. Mine." && kept.allSatisfy { $0.source != .hub })
    }

    @Test func twoHubsWithTheSameSkillNameKeepTheFirst() throws {
        let store = try makeStore()
        let report = try store.sync([item("alpha", hub: "one"), item("alpha", hub: "two", body: "1. Other.")])
        #expect(report == SkillSyncReport(added: 1, skipped: 1))
        #expect(try store.all().first?.sourceRef == "one/alpha")
    }

    @Test func aHubSkillWithoutAReferenceIsRemoved() throws {
        let store = try makeStore()
        let stray = SkillRecord(name: "stray", summary: "Stray.", body: "1. x", source: .hub, sourceRef: nil)
        store.context.insert(stray)
        try store.context.save()
        #expect(try store.sync([item("alpha")]).removed == 1)
        #expect(try store.all().map(\.name) == ["alpha"])
    }

    @Test func theStoreStillStopsAtTheLimit() throws {
        let store = try makeStore()
        let first = (0..<SkillStore.limit).map { item("skill-\($0)") }
        #expect(try store.sync(first).added == 100)
        let report = try store.sync(first + [item("one-more")])
        #expect(report == SkillSyncReport(added: 0, updated: 0, removed: 0, skipped: 1))
        #expect(try store.all().count == 100)
    }

    @Test func aSkillWithNoUsableDescriptionOrNameIsSkipped() throws {
        let store = try makeStore()
        let report = try store.sync([item("good"), item("no-words", description: nil), item("Bad Name")])
        #expect(report == SkillSyncReport(added: 1, skipped: 2))
    }

    @Test func theSummaryNamesOnlyWhatChanged() {
        #expect(SkillSyncReport(added: 1, updated: 2, removed: 3, skipped: 4).summary == "1 added, 2 updated, 3 removed, 4 skipped.")
        #expect(SkillSyncReport(updated: 1).summary == "1 updated.")
    }
}
