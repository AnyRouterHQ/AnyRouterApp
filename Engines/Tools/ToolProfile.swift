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
    /// be dropped, the clock comes first, then the calculator, web search, reading a page, then the rest, each group in its
    /// given order. Four tools (Apple) are therefore the clock, the calculator, search and one page reader.
    func shaped(_ specs: [ToolSpec]) -> [ToolSpec] {
        var list = specs
        if list.count > maxTools {
            let ranked = list.enumerated().sorted { lhs, rhs in
                let (a, b) = (Self.priority(of: lhs.element.name), Self.priority(of: rhs.element.name))
                return a != b ? a < b : lhs.offset < rhs.offset
            }
            list = ranked.prefix(maxTools).map { $0.element }
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

    private static func priority(of name: String) -> Int {
        let lowered = name.lowercased()
        if lowered.contains("date") { return 0 }
        if lowered.contains("calculator") { return 1 }
        if lowered.contains("search") { return 2 }
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
