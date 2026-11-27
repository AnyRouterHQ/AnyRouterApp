import Foundation
import SwiftData
import Testing
@testable import AnyRouter

@MainActor
struct ThreadActionsTests {
    private func context() throws -> ModelContext {
        ModelContext(try ModelContainer.anyRouter(inMemory: true))
    }

    @Test func togglePinFlipsAndRestores() {
        let thread = ThreadRecord(title: "A")
        ThreadActions.togglePin(thread)
        #expect(thread.isPinned)
        ThreadActions.togglePin(thread)
        #expect(!thread.isPinned)
    }

    @Test func renameTrimsAndBlankKeepsOldTitle() {
        let thread = ThreadRecord(title: "Old")
        ThreadActions.rename(thread, to: "  New  ")
        #expect(thread.title == "New")
        ThreadActions.rename(thread, to: "   ")
        #expect(thread.title == "New")
    }

    @Test func renameMakesTheTitleTheUsersAndABlankNameDoesNot() {
        let thread = ThreadRecord(title: "Old")
        thread.titleSource = .firstMessage
        ThreadActions.rename(thread, to: "   ")
        #expect(thread.titleSource == .firstMessage, "a blank name changes nothing")
        ThreadActions.rename(thread, to: "Mine")
        #expect(thread.titleSource == .user)
    }

    @Test func deleteRemovesOnlyThatThread() throws {
        let context = try context()
        let a = ThreadRecord(title: "A"), b = ThreadRecord(title: "B")
        context.insert(a); context.insert(b)
        ThreadActions.delete(a, in: context)
        let titles = try context.fetch(FetchDescriptor<ThreadRecord>()).map(\.title)
        #expect(titles == ["B"])
    }

    @Test func deleteAllRemovesThreadsAndTheirMessages() throws {
        let context = try context()
        let thread = ThreadRecord(title: "A")
        context.insert(thread)
        thread.messages.append(MessageRecord(role: .user, content: "hi"))
        try context.save()
        ThreadActions.deleteAll(in: context)
        #expect(try context.fetch(FetchDescriptor<ThreadRecord>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<MessageRecord>()).isEmpty)
    }
}
