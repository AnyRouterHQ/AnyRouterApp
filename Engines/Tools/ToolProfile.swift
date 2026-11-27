import Foundation

/// How much tool text a model can take. A small model has a context of a few thousand tokens, so it is offered
/// fewer tools with shorter descriptions, and a tool answer is cut before it goes back into the chat.
struct ToolProfile: Equatable, Sendable {
    var maxTools: Int
    var maxResultCharacters: Int
    var maxDescriptionCharacters: Int?

    /// Cloud models.
    static let full = ToolProfile(maxTools: Int.max, maxResultCharacters: MCPToolHost.maxResultCharacters, maxDescriptionCharacters: nil)
    /// Local models: four tools at most, like Apple's, because a local context is small and every tool is prompt text.
    static let compact = ToolProfile(maxTools: 4, maxResultCharacters: 6_000, maxDescriptionCharacters: 160)
    /// Apple's model: a 4,096-token window that its instructions, every tool schema and the chat share, and Apple advises a
    /// handful of tools. The date tool and the calculator stay in the first four (see `priority`).
    static let apple = ToolProfile(maxTools: 4, maxResultCharacters: 6_000, maxDescriptionCharacters: 160)

    static func forModel(_ source: ModelSource?) -> ToolProfile {
        switch source {
        case .apple: .apple
        case .gguf, .mlx: .compact
        case .anyrouter, nil: .full
        }
    }

    /// At most `maxTools` specs with short descriptions. This is the only cap on the tools a model sees. When tools must
    /// be dropped, the first clock comes first, then the first calculator, web search and page reader, then the rest in
    /// their given order. Four tools (Apple) are therefore the clock, the calculator, search and one page reader, even
    /// when a docs search or a second page reader is on too.
    func shaped(_ specs: [ToolSpec]) -> [ToolSpec] {
        var list = specs
        if list.count > maxTools {
            let ranks = Self.ranks(of: list.map(\.name))
            let order = list.indices.sorted { ranks[$0] != ranks[$1] ? ranks[$0] < ranks[$1] : $0 < $1 }
            list = order.prefix(maxTools).map { list[$0] }
        }
        guard let limit = maxDescriptionCharacters else { return list }
        return list.map { spec in
            var short = spec
            short.description = Self.shortened(spec.description, limit: limit)
            return short
        }
    }

    func clipped(_ text: String) -> String {
        MCPToolHost.clip(text, limit: maxResultCharacters)
    }

    /// Only the first tool of each kind keeps its kind's rank; a second one ranks with the rest.
    private static func ranks(of names: [String]) -> [Int] {
        var taken = Set<Int>()
        return names.map { name in
            let rank = Self.kind(of: name)
            return rank < 4 && taken.insert(rank).inserted ? rank : 4
        }
    }

    private static func kind(of name: String) -> Int {
        let lowered = name.lowercased()
        if lowered.contains("date") { return 0 }
        if lowered.contains("calculator") { return 1 }
        if lowered.contains("web_search") || lowered.hasSuffix("firecrawl_search") { return 2 }
        if ["fetch_url", "web_fetch", "scrape", "read_url"].contains(where: { lowered.contains($0) }) { return 3 }
        return 4
    }

    /// One line: whitespace collapsed, cut after a sentence when one fits, else at a word, with an ellipsis.
    static func shortened(_ text: String, limit: Int) -> String {
        let flat = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard flat.count > limit else { return flat }
        let head = String(flat.prefix(limit))
        if let end = head.lastIndex(where: { ".!?".contains($0) }), head.distance(from: head.startIndex, to: end) >= limit / 3 {
            return String(head[...end])
        }
        let words = head.lastIndex(of: " ").map { String(head[..<$0]) } ?? head
        return words + "…"
    }
}
