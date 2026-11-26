import Foundation

/// How much tool text a model can take. A small model has a context of a few thousand tokens, so it is offered
/// fewer tools with shorter descriptions, and a tool answer is cut before it goes back into the chat.
struct ToolProfile: Equatable, Sendable {
    var maxTools: Int
    var maxResultCharacters: Int
    var maxDescriptionCharacters: Int?

    /// Cloud models.
    static let full = ToolProfile(maxTools: Int.max, maxResultCharacters: MCPToolHost.maxResultCharacters, maxDescriptionCharacters: nil)
    /// Apple's model and local models.
    static let compact = ToolProfile(maxTools: 8, maxResultCharacters: 6_000, maxDescriptionCharacters: 160)

    static func forModel(_ source: ModelSource?) -> ToolProfile {
        switch source {
        case .apple, .gguf, .mlx: .compact
        case .anyrouter, nil: .full
        }
    }

    /// At most `maxTools` specs with short descriptions. When tools must be dropped, search comes first, then reading
    /// a page, then the calculator and the clock, then the rest, each group in its given order.
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
        if lowered.contains("search") { return 0 }
        if ["fetch_url", "web_fetch", "scrape", "read_url"].contains(where: { lowered.contains($0) }) { return 1 }
        if ["calculator", "date"].contains(where: { lowered.contains($0) }) { return 2 }
        return 3
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
