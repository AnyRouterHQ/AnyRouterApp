import Foundation

/// The words and rules of the cloud model's `memory` and `search_chats` tools (agent design 2.4). One `memory` tool
/// with an action costs one schema; `search_chats` finds earlier chats with no model call.
enum MemoryToolLogic {
    static let memoryName = "memory"
    static let memoryDescription = """
        The user's saved memory: short statements about who they are and how they want answers. \
        search finds items (an empty query lists the newest); add saves one thing the user stated, never a guess, \
        at most 280 characters; remove deletes one by its id from search. The user sees every change and can undo it.
        """
    static let memorySchema = #"{"type":"object","properties":{"action":{"type":"string","enum":["search","add","remove"]},"query":{"type":"string","description":"search: words to look for"},"text":{"type":"string","description":"add: one short statement"},"kind":{"type":"string","enum":["profile","preference","fact"],"description":"add: who the user is, how they want answers, or anything else"},"id":{"type":"string","description":"remove: an id from search"}},"required":["action"]}"#

    static let searchChatsName = "search_chats"
    static let searchChatsDescription = "Search the user's earlier chats in this app. Returns at most 5 chats, each with its title, date, summary and one matching message."
    static let searchChatsSchema = #"{"type":"object","properties":{"query":{"type":"string","description":"Words to look for"}},"required":["query"]}"#

    static let maxSearchItems = 10
    static let maxChats = 5
    static let excerptLimit = 300

    enum Request: Equatable {
        case search(String)
        case add(String, MemoryKind)
        case remove(UUID)
    }

    /// The kinds the model may save. Pinned notes are the user's own; chat summaries are written by the app.
    static let modelKinds: [MemoryKind] = [.profile, .preference, .fact]

    static func request(from arguments: JSONValue) throws -> Request {
        switch arguments["action"]?.string {
        case "search":
            return .search(arguments["query"]?.string ?? "")
        case "add":
            guard let text = arguments["text"]?.string, !text.isEmpty else { throw BuiltInToolError("Missing the \"text\" argument.") }
            let kind = arguments["kind"]?.string.flatMap(MemoryKind.init(rawValue:)).flatMap { modelKinds.contains($0) ? $0 : nil }
            return .add(text, kind ?? .fact)
        case "remove":
            guard let id = arguments["id"]?.string.flatMap(UUID.init(uuidString:)) else {
                throw BuiltInToolError("Missing or unknown \"id\". Search first and use an id from the results.")
            }
            return .remove(id)
        default:
            throw BuiltInToolError("\"action\" must be search, add or remove.")
        }
    }

    struct Item: Equatable, Sendable {
        let id: UUID
        let kind: MemoryKind
        let text: String
    }

    static func render(_ items: [Item]) -> String {
        guard !items.isEmpty else { return "No saved memory matches." }
        return items.map { "- [\($0.id.uuidString)] (\($0.kind.rawValue)) \($0.text)" }.joined(separator: "\n")
    }

    /// What the model reads back after an add or a remove.
    static func reply(to outcome: MemoryUpdate.Outcome) -> String {
        switch outcome {
        case .saved: "Saved. The user sees it and can undo it."
        case .alreadySaved: "Already saved."
        case .refused(let reason): "Not saved: " + reason
        case .removed: "Removed. The user sees it and can undo it."
        case .undone: "Undone."
        }
    }

    /// A chat whose every reply came from AnyRouter. A reply with no model id counts as from this device, the safe side.
    static func isCloudChat(replyModelIDs: [String?]) -> Bool {
        replyModelIDs.allSatisfy { $0?.hasPrefix(ModelSource.anyrouter.rawValue + "/") == true }
    }

    struct FoundChat: Equatable, Sendable {
        let title: String
        let date: Date
        let summary: String?
        let excerpt: String
    }

    static func render(chats: [FoundChat]) -> String {
        guard !chats.isEmpty else { return "No earlier chat matches." }
        return chats.map { chat in
            var lines = ["## \(chat.title) (\(chat.date.formatted(.iso8601.year().month().day())))"]
            if let summary = chat.summary { lines.append("Summary: " + summary) }
            lines.append("Message: " + chat.excerpt)
            return lines.joined(separator: "\n")
        }.joined(separator: "\n\n")
    }

    /// At most `limit` characters of the message, around the first word of the query it holds.
    static func excerpt(_ text: String, query: String, limit: Int = excerptLimit) -> String {
        let characters = Array(text)
        guard characters.count > limit else { return text }
        let hit = MemoryRecallLogic.words(query).lazy.compactMap { text.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) }.first
        let center = hit.map { text.distance(from: text.startIndex, to: $0.lowerBound) } ?? 0
        let start = min(max(0, center - limit / 3), characters.count - limit)
        let end = start + limit
        return (start > 0 ? "\u{2026}" : "") + String(characters[start..<end]) + (end < characters.count ? "\u{2026}" : "")
    }
}
