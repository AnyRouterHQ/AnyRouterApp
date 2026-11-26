import Foundation
import SwiftData
import Testing
@testable import AnyRouter

@MainActor
struct ThreadSearchLogicTests {
    private func makeContext() throws -> ModelContext {
        ModelContext(try ModelContainer.anyRouter(inMemory: true))
    }

    private func thread(_ context: ModelContext, _ title: String, pinned: Bool = false,
                        age: TimeInterval = 0, messages: [String] = []) -> ThreadRecord {
        let t = ThreadRecord(title: title, createdAt: Date(timeIntervalSince1970: 1_000_000 - age), isPinned: pinned)
        context.insert(t)
        for (index, text) in messages.enumerated() {
            let m = MessageRecord(role: .user, content: text, createdAt: t.createdAt.addingTimeInterval(Double(index)))
            context.insert(m)
            m.thread = t
        }
        return t
    }

    private func titles(_ hits: [ThreadSearchLogic.Hit]) -> [String] { hits.map(\.thread.title) }

    @Test func blankQueryGivesRecentsNewestFirstWithoutSnippets() throws {
        let c = try makeContext()
        let all = [thread(c, "old", age: 100), thread(c, "new", age: 10), thread(c, "pinned", pinned: true, age: 50)]
        let hits = ThreadSearchLogic.results(in: all, query: "  ")
        #expect(titles(hits) == ["new", "pinned", "old"])
        #expect(hits.allSatisfy { $0.snippet == nil })
    }

    @Test func recentsStopAtTwentyThreads() throws {
        let c = try makeContext()
        let all = (0..<25).map { thread(c, "chat \($0)", age: Double($0)) }
        let hits = ThreadSearchLogic.results(in: all, query: "")
        #expect(hits.count == 20)
        #expect(hits.first?.thread.title == "chat 0")
        #expect(hits.last?.thread.title == "chat 19")
    }

    @Test func titleMatchHasNoSnippet() throws {
        let c = try makeContext()
        let hits = ThreadSearchLogic.results(in: [thread(c, "Trip to Lisbon"), thread(c, "Other")], query: "lisbon")
        #expect(titles(hits) == ["Trip to Lisbon"])
        #expect(hits.first?.snippet == nil)
    }

    @Test func bodyMatchCarriesTheTextAroundIt() throws {
        let c = try makeContext()
        let match = thread(c, "Untitled", messages: ["hello", "how do actors work in Swift", "actors again, later"])
        let hits = ThreadSearchLogic.results(in: [match, thread(c, "Other", messages: ["hello"])], query: "ACTORS")
        #expect(titles(hits) == ["Untitled"])
        #expect(hits.first?.id == match.id)
        #expect(hits.first?.snippet == "how do actors work in Swift", "the first message that matches, in creation order")
    }

    @Test func longBodyIsCutAroundTheMatchOnOneLine() throws {
        let c = try makeContext()
        let text = String(repeating: "a", count: 100) + "\nNEEDLE\n" + String(repeating: "b", count: 100)
        let snippet = try #require(ThreadSearchLogic.results(in: [thread(c, "t", messages: [text])], query: "needle").first?.snippet)
        #expect(snippet.hasPrefix("…") && snippet.hasSuffix("…"))
        #expect(snippet.contains(" NEEDLE "))
        #expect(!snippet.contains("\n"))
        #expect(snippet.count == 1 + 39 + 1 + 6 + 1 + 39 + 1, "40 characters kept each side of the match, newlines became spaces")
    }

    @Test func caseAndDiacriticsAreIgnoredInBothDirections() throws {
        let c = try makeContext()
        let all = [thread(c, "Du lịch Đà Nẵng"), thread(c, "Café plans"), thread(c, "Other")]
        #expect(titles(ThreadSearchLogic.results(in: all, query: "du lich")) == ["Du lịch Đà Nẵng"])
        #expect(titles(ThreadSearchLogic.results(in: all, query: "da nang")) == ["Du lịch Đà Nẵng"])
        #expect(titles(ThreadSearchLogic.results(in: all, query: "CAFE")) == ["Café plans"])
        #expect(titles(ThreadSearchLogic.results(in: all, query: "cafÉ")) == ["Café plans"])
    }

    @Test func vietnameseBodyKeepsItsAccentsInTheSnippet() throws {
        let c = try makeContext()
        let all = [thread(c, "Notes", messages: ["Kế hoạch du lịch Đà Lạt tuần sau"])]
        #expect(ThreadSearchLogic.results(in: all, query: "da lat").first?.snippet == "Kế hoạch du lịch Đà Lạt tuần sau")
    }

    @Test func snippetStillShowsWhenFoldingChangesTheLength() throws {
        let c = try makeContext()
        let all = [thread(c, "Notes", messages: ["Die Straße ist lang"])]
        #expect(ThreadSearchLogic.results(in: all, query: "strasse").first?.snippet == "Die Straße ist lang")
    }

    @Test func matchesAreNewestFirstAndPinnedAreNotMovedUp() throws {
        let c = try makeContext()
        let all = [thread(c, "swift old", age: 100), thread(c, "swift pinned", pinned: true, age: 50), thread(c, "swift new", age: 10)]
        #expect(titles(ThreadSearchLogic.results(in: all, query: "swift")) == ["swift new", "swift pinned", "swift old"])
    }

    @Test func noMatchIsEmpty() throws {
        let c = try makeContext()
        #expect(ThreadSearchLogic.results(in: [thread(c, "a", messages: ["b"])], query: "zzz").isEmpty)
    }
}
