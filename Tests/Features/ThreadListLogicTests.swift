import Foundation
import SwiftData
import Testing
@testable import AnyRouter

@MainActor
struct ThreadListLogicTests {
    private func makeContext() throws -> ModelContext {
        ModelContext(try ModelContainer.anyRouter(inMemory: true))
    }

    private func thread(_ context: ModelContext, _ title: String, pinned: Bool = false,
                        age: TimeInterval = 0, messages: [String] = []) -> ThreadRecord {
        let t = ThreadRecord(title: title, createdAt: Date(timeIntervalSince1970: 1_000_000 - age), isPinned: pinned)
        context.insert(t)
        for text in messages {
            let m = MessageRecord(role: .user, content: text)
            context.insert(m)
            m.thread = t
        }
        return t
    }

    @Test func pinnedAreSeparatedAndEachGroupIsNewestFirst() throws {
        let c = try makeContext()
        let all = [
            thread(c, "old", age: 100), thread(c, "pinned old", pinned: true, age: 500),
            thread(c, "new", age: 10), thread(c, "pinned new", pinned: true, age: 50),
        ]
        let s = ThreadListLogic.sections(from: all, query: "")
        #expect(s.pinned.map(\.title) == ["pinned new", "pinned old"])
        #expect(s.recent.map(\.title) == ["new", "old"])
    }

    @Test func queryMatchesTitleIgnoringCaseAndDiacritics() throws {
        let c = try makeContext()
        let all = [thread(c, "Café plans"), thread(c, "Other")]
        let s = ThreadListLogic.sections(from: all, query: "cafe")
        #expect(s.recent.map(\.title) == ["Café plans"])
        #expect(s.pinned.isEmpty)
    }

    @Test func queryMatchesMessageContent() throws {
        let c = try makeContext()
        let all = [thread(c, "Untitled", messages: ["how do actors work in Swift"]),
                   thread(c, "Other", messages: ["hello"])]
        #expect(ThreadListLogic.sections(from: all, query: "ACTORS").recent.map(\.title) == ["Untitled"])
    }

    @Test func blankQueryKeepsEverythingAndNoMatchIsEmpty() throws {
        let c = try makeContext()
        let all = [thread(c, "a")]
        #expect(ThreadListLogic.sections(from: all, query: "  ").recent.count == 1)
        #expect(ThreadListLogic.sections(from: all, query: "zzz").isEmpty)
    }

    @Test func titleFromFirstMessage() {
        #expect(ThreadListLogic.title(fromFirstMessage: "Hello\nsecond line") == "Hello")
        #expect(ThreadListLogic.title(fromFirstMessage: "   ") == "New chat")
        let long = String(repeating: "x", count: 80)
        #expect(ThreadListLogic.title(fromFirstMessage: long) == String(repeating: "x", count: 48) + "…")
    }

    @Test func renameKeepsOldTitleWhenBlank() {
        #expect(ThreadListLogic.renamed("  ", current: "Keep") == "Keep")
        #expect(ThreadListLogic.renamed(" New ", current: "Keep") == "New")
    }
}
