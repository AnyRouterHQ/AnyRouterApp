import Foundation
import SwiftData
import Testing
@testable import AnyRouter

@MainActor
struct ThreadArchiveTests {
    private func context() throws -> ModelContext {
        ModelContext(try ModelContainer.anyRouter(inMemory: true))
    }

    private func thread(_ c: ModelContext, _ title: String, archived: Bool = false, age: TimeInterval = 0) -> ThreadRecord {
        let t = ThreadRecord(title: title, createdAt: Date(timeIntervalSince1970: 1_000_000 - age))
        t.isArchived = archived
        c.insert(t)
        return t
    }

    @Test func aNewRecordIsNotArchived() {
        #expect(!ThreadRecord(title: "A").isArchived)
    }

    @Test func aStoreWrittenBeforeArchivingReadsFalse() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("archive-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }
        let id = UUID()
        do {
            let c = ModelContext(try ModelContainer.anyRouter(storeURL: url))
            c.insert(ThreadRecord(id: id, title: "Old"))
            try c.save()
        }
        let reopened = ModelContext(try ModelContainer.anyRouter(storeURL: url))
        let found = try reopened.fetch(FetchDescriptor<ThreadRecord>(predicate: #Predicate { $0.id == id }))
        #expect(found.first?.isArchived == false)
    }

    @Test func archivedChatsLeaveSectionsAndSearchButStayInTheArchivedList() throws {
        let c = try context()
        let all = [thread(c, "keep", age: 1), thread(c, "gone", archived: true, age: 2), thread(c, "older gone", archived: true, age: 9)]
        let pinnedArchived = thread(c, "pinned gone", archived: true)
        pinnedArchived.isPinned = true
        let sections = ThreadListLogic.sections(from: all + [pinnedArchived])
        #expect(sections.recent.map(\.title) == ["keep"])
        #expect(sections.pinned.isEmpty)
        #expect(ThreadSearchLogic.results(in: all, query: "").map(\.thread.title) == ["keep"])
        #expect(ThreadSearchLogic.results(in: all, query: "gone").isEmpty)
        #expect(ThreadListLogic.archived(from: all).map(\.title) == ["gone", "older gone"])
    }

    @Test func toggleArchiveRoundTripsAndKeepsThePin() {
        let t = ThreadRecord(title: "A", isPinned: true)
        ThreadActions.toggleArchive(t)
        #expect(t.isArchived && t.isPinned)
        ThreadActions.toggleArchive(t)
        #expect(!t.isArchived)
    }

    @Test func archivingTheOpenChatStartsANewOneAndOthersStay() {
        let shell = ShellModel()
        let id = UUID()
        shell.select(threadID: id, closeSidebar: false)
        shell.threadArchived(UUID())
        #expect(shell.selectedThreadID == id)
        shell.threadArchived(id)
        #expect(shell.selectedThreadID == nil)
    }
}
