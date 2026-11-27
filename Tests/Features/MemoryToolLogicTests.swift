import Foundation
import Testing
@testable import AnyRouter

struct MemoryToolLogicTests {
    private func request(_ fields: [String: JSONValue]) throws -> MemoryToolLogic.Request {
        try MemoryToolLogic.request(from: .object(fields))
    }

    private func message(_ work: () throws -> Void) -> String? {
        do { try work() } catch { return error.localizedDescription }
        return nil
    }

    @Test func eachActionReadsItsArguments() throws {
        let id = UUID()
        #expect(try request(["action": .string("search"), "query": .string("dog")]) == .search("dog"))
        #expect(try request(["action": .string("search")]) == .search(""))
        #expect(try request(["action": .string("add"), "text": .string("Short answers."), "kind": .string("preference")]) == .add("Short answers.", .preference))
        #expect(try request(["action": .string("add"), "text": .string("Likes tea."), "kind": .string("note")]) == .add("Likes tea.", .fact), "pinned notes are the user's own")
        #expect(try request(["action": .string("add"), "text": .string("Likes tea.")]) == .add("Likes tea.", .fact))
        #expect(try request(["action": .string("remove"), "id": .string(id.uuidString)]) == .remove(id))
    }

    @Test func aBadCallSaysHowToFixIt() {
        #expect(message { _ = try request(["action": .string("add")]) }?.contains("text") == true)
        #expect(message { _ = try request(["action": .string("remove"), "id": .string("seven")]) }?.contains("Search first") == true)
        #expect(message { _ = try request(["action": .string("forget")]) }?.contains("search, add or remove") == true)
    }

    @Test func searchResultsCarryTheIdForARemove() {
        let id = UUID()
        #expect(MemoryToolLogic.render([]) == "No saved memory matches.")
        #expect(MemoryToolLogic.render([.init(id: id, kind: .fact, text: "My dog is called Mochi")]) == "- [\(id.uuidString)] (fact) My dog is called Mochi")
    }

    @Test func theModelIsToldWhatHappened() {
        #expect(MemoryToolLogic.reply(to: .saved).hasPrefix("Saved."))
        #expect(MemoryToolLogic.reply(to: .alreadySaved) == "Already saved.")
        #expect(MemoryToolLogic.reply(to: .refused("Facts is full.")) == "Not saved: Facts is full.")
        #expect(MemoryToolLogic.reply(to: .removed).hasPrefix("Removed."))
        #expect(MemoryToolLogic.reply(to: .undone) == "Undone.")
    }

    @Test func aChatIsACloudChatOnlyWhenEveryReplyCameFromAnyRouter() {
        #expect(MemoryToolLogic.isCloudChat(replyModelIDs: ["anyrouter/openai/gpt-5", "anyrouter/auto"]))
        #expect(!MemoryToolLogic.isCloudChat(replyModelIDs: ["anyrouter/auto", "apple/foundation"]))
        #expect(!MemoryToolLogic.isCloudChat(replyModelIDs: [nil]), "an unknown reply counts as from this device")
    }

    @Test func foundChatsShowTitleDateSummaryAndMessage() {
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        #expect(MemoryToolLogic.render(chats: []) == "No earlier chat matches.")
        let text = MemoryToolLogic.render(chats: [
            .init(title: "Trip to Da Lat", date: date, summary: "Planned three days.", excerpt: "Book the bus."),
            .init(title: "Bread", date: date, summary: nil, excerpt: "Rye."),
        ])
        #expect(text == "## Trip to Da Lat (\(date.formatted(.iso8601.year().month().day())))\nSummary: Planned three days.\nMessage: Book the bus.\n\n## Bread (\(date.formatted(.iso8601.year().month().day())))\nMessage: Rye.")
    }

    @Test func anExcerptIsCutAroundTheFirstWordFound() {
        #expect(MemoryToolLogic.excerpt("Short.", query: "short", limit: 20) == "Short.")
        let long = String(repeating: "a ", count: 30) + "Mochi" + String(repeating: " b", count: 30)
        let middle = MemoryToolLogic.excerpt(long, query: "mochi", limit: 30)
        #expect(middle.hasPrefix("\u{2026}") && middle.hasSuffix("\u{2026}") && middle.contains("Mochi"))
        let start = MemoryToolLogic.excerpt(long, query: "nothing", limit: 30)
        #expect(!start.hasPrefix("\u{2026}") && start.hasSuffix("\u{2026}"))
        let end = MemoryToolLogic.excerpt(long + " Zed", query: "zed", limit: 30)
        #expect(end.hasPrefix("\u{2026}") && end.hasSuffix("Zed"))
    }
}
