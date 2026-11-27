import Foundation
import SwiftData
import Testing
@testable import AnyRouter

@MainActor
struct MemoryStoreTests {
    private func makeStore() throws -> MemoryStore {
        MemoryStore(context: ModelContext(try ModelContainer.anyRouter(inMemory: true)))
    }

    private func thrown<T>(_ work: () throws -> T) -> MemoryError? {
        do { _ = try work() } catch { return error as? MemoryError }
        return nil
    }

    private func fill(_ store: MemoryStore, kind: MemoryKind, count: Int) {
        for index in 0..<count {
            let record = MemoryRecord(
                kind: kind, text: "item \(index)", origin: .typedInSettings, scope: .everywhere,
                now: Date(timeIntervalSince1970: Double(index)))
            store.context.insert(record)
        }
    }

    @Test func addTrimsAndTypedInSettingsIsEverywhere() throws {
        let store = try makeStore()
        let record = try store.add("  I live in Hue.\n", kind: .profile)
        #expect(record.text == "I live in Hue.")
        #expect(record.origin == .typedInSettings)
        #expect(record.scope == .everywhere, "typed items go to the model you chat with")
        #expect(try store.all().count == 1)
    }

    @Test func addKeepsTheSourceChatAndScopeOfAnItemFromAChat() throws {
        let store = try makeStore()
        let thread = UUID(), message = UUID()
        let record = try store.add("Likes tram 28.", kind: .fact, origin: .extracted, scope: .deviceOnly, sourceThreadID: thread, sourceMessageID: message)
        #expect(record.scope == .deviceOnly && record.origin == .extracted)
        #expect(record.sourceThreadID == thread && record.sourceMessageID == message)
    }

    @Test func emptyAndBlankTextIsRefused() throws {
        let store = try makeStore()
        #expect(thrown { try store.add("", kind: .note) } == .empty)
        #expect(thrown { try store.add(" \n ", kind: .note) } == .empty)
        #expect(try store.all().isEmpty)
    }

    @Test func textIsLimitedTo280CharactersAndASummaryTo600() throws {
        let store = try makeStore()
        _ = try store.add(String(repeating: "a", count: 280), kind: .fact)
        #expect(thrown { try store.add(String(repeating: "b", count: 281), kind: .fact) } == .tooLong(limit: 280))
        _ = try store.add(String(repeating: "c", count: 600), kind: .chatSummary)
        #expect(thrown { try store.add(String(repeating: "d", count: 601), kind: .chatSummary) } == .tooLong(limit: 600))
        #expect(try store.all().count == 2)
    }

    @Test func duplicatesAreRefusedIgnoringCaseAndDiacriticsAcrossKinds() throws {
        let store = try makeStore()
        _ = try store.add("Tôi ăn chay", kind: .preference)
        #expect(thrown { try store.add("TOI AN CHAY", kind: .fact) } == .duplicate)
        #expect(thrown { try store.add("  tôi ăn chay  ", kind: .preference) } == .duplicate)
        _ = try store.add("Tôi ăn chay mỗi ngày", kind: .preference)
        #expect(try store.all().count == 2)
    }

    @Test func editChangesTextAndTimeAndKeepsEverythingElse() throws {
        let store = try makeStore()
        let record = try store.add("Short answers", kind: .preference, now: Date(timeIntervalSince1970: 1))
        try store.edit(record, text: "  Very short answers ", now: Date(timeIntervalSince1970: 9))
        #expect(record.text == "Very short answers")
        #expect(record.updatedAt == Date(timeIntervalSince1970: 9) && record.createdAt == Date(timeIntervalSince1970: 1))
        #expect(record.kind == .preference)
    }

    @Test func editRefusesEmptyTooLongAndTheTextOfAnotherItemButNotItsOwn() throws {
        let store = try makeStore()
        let first = try store.add("One", kind: .note)
        _ = try store.add("Two", kind: .note)
        #expect(thrown { try store.edit(first, text: " ") } == .empty)
        #expect(thrown { try store.edit(first, text: String(repeating: "x", count: 281)) } == .tooLong(limit: 280))
        #expect(thrown { try store.edit(first, text: "two") } == .duplicate)
        try store.edit(first, text: "ONE")
        #expect(first.text == "ONE")
    }

    @Test func deleteRemovesOneAndDeleteAllRemovesEverything() throws {
        let store = try makeStore()
        let first = try store.add("One", kind: .note)
        _ = try store.add("Two", kind: .fact)
        try store.delete(first)
        #expect(try store.all().map(\.text) == ["Two"])
        try store.deleteAll()
        #expect(try store.all().isEmpty)
    }

    @Test func listGroupsInPageOrderHidesEmptyGroupsAndShowsNewestEditFirst() throws {
        let store = try makeStore()
        _ = try store.add("old fact", kind: .fact, now: Date(timeIntervalSince1970: 1))
        _ = try store.add("summary", kind: .chatSummary, now: Date(timeIntervalSince1970: 2))
        _ = try store.add("new fact", kind: .fact, now: Date(timeIntervalSince1970: 3))
        _ = try store.add("name", kind: .profile, now: Date(timeIntervalSince1970: 4))
        _ = try store.add("pinned", kind: .note, now: Date(timeIntervalSince1970: 5))
        let groups = try store.list()
        #expect(groups.map(\.kind) == [.profile, .note, .fact, .chatSummary])
        #expect(groups.map(\.id) == groups.map(\.kind))
        #expect(groups[2].records.map(\.text) == ["new fact", "old fact"])
        #expect(MemoryKind.pageOrder.map(\.groupTitle) == ["About you", "Preferences", "Pinned notes", "Facts", "Chat summaries"])
        #expect(MemoryKind.addable.map(\.addTitle) == ["About you", "Preference", "Note", "Fact"])
        #expect(MemoryKind.chatSummary.addTitle == "Chat summary")
    }

    @Test func profilePreferencesAndNotesShareACapOfSixtyAndNothingIsRemoved() throws {
        let store = try makeStore()
        fill(store, kind: .profile, count: 30)
        fill(store, kind: .preference, count: 20)
        fill(store, kind: .note, count: 10)
        let refused = thrown { try store.add("one more", kind: .preference) }
        guard case .full(let name, let limit, let oldest)? = refused else {
            Issue.record("expected the cap to refuse the write, got \(String(describing: refused))")
            return
        }
        #expect(limit == 60 && name.contains("Preferences"))
        #expect(oldest == ["item 0", "item 0", "item 0"], "the least recently touched items of the three kinds")
        #expect(try store.all().count == 60, "a refused write removes nothing")
        _ = try store.add("a fact still fits", kind: .fact)
        _ = try store.add("a summary still fits", kind: .chatSummary)
    }

    @Test func factsHaveTheirOwnCapOfFiveHundred() throws {
        let store = try makeStore()
        fill(store, kind: .fact, count: 500)
        #expect(thrown { try store.add("one more", kind: .fact) } != nil)
        _ = try store.add("a note still fits", kind: .note)
    }

    @Test func theErrorNamesTheOldestUnusedItemsAndPrefersItemsNeverUsed() throws {
        let store = try makeStore()
        fill(store, kind: .fact, count: 500)
        let used = try store.all().filter { ["item 0", "item 1"].contains($0.text) }
        for record in used {
            record.useCount = 3
            record.lastUsedAt = Date(timeIntervalSince1970: 100_000)
        }
        let seventh = try store.all().first { $0.text == "item 7" }
        let long = try #require(seventh)
        long.text = String(repeating: "z", count: 60)
        let firstRefusal = thrown { try store.add("new", kind: .fact) }
        let message = try #require(firstRefusal?.errorDescription)
        #expect(message.contains("Facts is full (500 items)"))
        #expect(message.contains("item 2") && message.contains("item 3") && message.contains("item 4"))
        #expect(!message.contains("item 0") && !message.contains("item 1"), "used items go last")
        let again = try #require(thrown { try store.add("new", kind: .fact) })
        #expect(again == .full(name: "Facts", limit: 500, oldestUnused: ["item 2", "item 3", "item 4"]))
        long.useCount = 0
        long.lastUsedAt = nil
        long.createdAt = Date(timeIntervalSince1970: -5)
        let lastRefusal = thrown { try store.add("new", kind: .fact) }
        let shortened = try #require(lastRefusal?.errorDescription)
        #expect(shortened.contains(String(repeating: "z", count: 40) + "\u{2026}"))
    }

    @Test func errorsReadAsPlainEnglish() {
        #expect(MemoryError.empty.errorDescription == "Write something to remember.")
        #expect(MemoryError.tooLong(limit: 280).errorDescription == "That is too long. Keep it to 280 characters or fewer.")
        #expect(MemoryError.duplicate.errorDescription == "You already have that in memory.")
    }

    @Test func sourceNamesTheChatWhenKnownElseHowItWasSaved() {
        let record = MemoryRecord(kind: .fact, text: "x", origin: .extracted, scope: .deviceOnly, sourceThreadID: UUID())
        #expect(MemoryStore.sourceText(of: record, threadTitle: "Trip to Da Lat") == "From the chat Trip to Da Lat")
        #expect(MemoryStore.sourceText(of: record, threadTitle: nil) == "Saved from a chat")
        let typed = MemoryRecord(kind: .note, text: "x", origin: .typedInSettings, scope: .everywhere)
        #expect(MemoryStore.sourceText(of: typed, threadTitle: "ignored") == "Typed in Settings")
        #expect(MemoryOrigin.allCases.map(\.label) == ["Typed in Settings", "You asked in a chat", "Saved from a chat", "Saved by the model"])
    }
}
