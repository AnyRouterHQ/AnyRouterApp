import Foundation

/// The cloud model's working notes for a chat (agent design 4, "Todo recitation", unit G5): a list of at most 10 short
/// items that each `notes` call replaces. From round `AgentLoop.recitesFromRound` on, each request repeats the list after
/// its last tool result, so the plan stays in view however many results come in between.
enum NotesLogic {
    static let name = "notes"
    static let maxItems = 10
    static let maxItemCharacters = 200
    static let description = """
        Your working notes for this chat: a list of at most 10 short items, such as the steps of a long task and which are \
        done. Each call replaces the whole list; send an empty list to clear it. In long runs the list is shown to you \
        again after the tool results.
        """
    static let schema = ##"{"type":"object","properties":{"items":{"type":"array","items":{"type":"string"},"maxItems":10,"description":"The whole new list."}},"required":["items"]}"##

    /// The items of a call: trimmed, empty ones dropped, each cut to `maxItemCharacters`.
    static func items(from arguments: JSONValue) throws -> [String] {
        guard let values = arguments["items"]?.array else { throw BuiltInToolError("Missing the \"items\" list.") }
        let items = values.compactMap { $0.string?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard items.count <= maxItems else { throw BuiltInToolError("At most \(maxItems) items. Merge or drop some.") }
        return items.map { String($0.prefix(maxItemCharacters)) }
    }

    /// What the model reads back after a call.
    static func reply(_ items: [String]) -> String {
        items.isEmpty ? "Notes cleared." : "Notes saved:\n" + numbered(items)
    }

    /// The notes as a request repeats them after its last tool result; nil when there are none.
    static func recitation(_ items: [String]) -> String? {
        items.isEmpty ? nil : "Your notes:\n" + numbered(items)
    }

    private static func numbered(_ items: [String]) -> String {
        items.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
    }
}
