import Foundation

/// Web search for a model that cannot call tools itself: the local GGUF and MLX models, until they have a tool loop (PLAN T7).
/// The app decides from the user's message whether fresh information is needed, runs one search, and puts the best
/// results in front of the question. Pure, so the decision and the text are tested without a model.
enum WebGrounding {
    static let maxResults = 3
    static let snippetCharacters = 500
    static let titleCharacters = 120
    static let maxQueryCharacters = 300
    /// A longer message is a pasted text or a task, not a question for the web.
    static let maxMessageCharacters = 500

    struct Source: Hashable, Sendable {
        var title: String
        var url: String
        var snippet: String
    }

    /// Models whose engine runs no tool loop.
    static func appliesTo(_ source: ModelSource) -> Bool { source == .gguf || source == .mlx }

    // MARK: Does this message need the web

    private static let phrases: [String] = [
        // The user asks for a search.
        "search the web", "search online", "search the internet", "search for", "web search", "look up", "lookup",
        "google", "on the internet", "on the web", "find online", "browse the web",
        // Now.
        "latest", "newest", "recent", "recently", "today", "tonight", "yesterday", "tomorrow", "currently",
        "right now", "this week", "this month", "this year", "this weekend", "breaking", "news", "headlines",
        "what's new", "whats new", "just released", "trending",
        // Things that change.
        "price", "prices", "stock", "stocks", "exchange rate", "weather", "forecast", "score", "scores", "who won",
        "election", "release date", "schedule", "standings", "rankings", "how much is", "how much does",
    ]

    private static let recentYear = try! NSRegularExpression(pattern: "\\b20(2[4-9]|[3-9][0-9])\\b")

    /// True for a question about now: a search request, a word like "latest" or "today", a price, the weather, a year
    /// from 2024 on. False for short or long texts, code, and everything the model can answer from what it knows.
    static func needsFreshInfo(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 8, trimmed.count <= maxMessageCharacters, !trimmed.contains("```") else { return false }
        let words = normalized(trimmed)
        if words.hasPrefix(" search ") { return true }
        if phrases.contains(where: { words.contains(" " + $0 + " ") }) { return true }
        return recentYear.firstMatch(in: words, range: NSRange(words.startIndex..., in: words)) != nil
    }

    /// Lowercase words with single spaces and a space at both ends, so a phrase can be found by its spaces.
    private static func normalized(_ text: String) -> String {
        let lowered = text.lowercased().replacingOccurrences(of: "\u{2019}", with: "'")
        let letters = lowered.map { $0.isLetter || $0.isNumber || $0 == "'" ? $0 : " " }
        return " " + String(letters).split(separator: " ").joined(separator: " ") + " "
    }

    /// The message as a search query: one line, not longer than `maxQueryCharacters`.
    static func query(from text: String) -> String {
        let flat = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return String(flat.prefix(maxQueryCharacters))
    }

    // MARK: Reading the answer

    /// The results in Exa's text answer: "Title:", "URL:", then "Highlights:" with the page text.
    static func parse(_ text: String) -> [Source] {
        var sources: [Source] = []
        var title: String?
        var url = ""
        var snippet: [String] = []
        var inText = false

        func flush() {
            guard let title, !title.isEmpty, !url.isEmpty else { return }
            let body = snippet.joined(separator: " ").split(whereSeparator: \.isWhitespace).joined(separator: " ")
            sources.append(Source(title: cut(title, titleCharacters), url: url, snippet: cut(body, snippetCharacters)))
        }

        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("Title: ") {
                flush()
                title = String(line.dropFirst("Title: ".count)).trimmingCharacters(in: .whitespaces)
                url = ""
                snippet = []
                inText = false
            } else if title != nil, !inText, line.hasPrefix("URL: ") {
                url = String(line.dropFirst("URL: ".count)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("Highlights:") || line.hasPrefix("Text:") {
                inText = true
            } else if inText {
                let plain = line.trimmingCharacters(in: .whitespaces)
                // Exa marks gaps with "..."; the host marks a cut answer with its own line.
                if plain != "...", !plain.hasPrefix("[Result cut at") { snippet.append(plain) }
            }
        }
        flush()
        return sources
    }

    private static func cut(_ text: String, _ limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit)).trimmingCharacters(in: .whitespaces) + "…"
    }

    // MARK: Putting it in front of the model

    /// The top results as context with one instruction on how to cite them. Nil when there are none.
    static func context(for sources: [Source]) -> String? {
        let top = sources.prefix(maxResults)
        guard !top.isEmpty else { return nil }
        var lines = [
            "Web search results, fetched just now. Use them when they help, and cite a source as [1], [2] or [3] after the claim it supports.",
        ]
        for (index, source) in top.enumerated() {
            lines += ["", "[\(index + 1)] \(source.title)", source.url, source.snippet]
        }
        return lines.joined(separator: "\n")
    }

    /// The history for one request, with the results in front of the last question of the user. The saved chat is not changed.
    static func applying(_ context: String, to messages: [ChatMessage]) -> [ChatMessage] {
        guard let index = messages.lastIndex(where: { $0.role == .user }) else { return messages }
        var copy = messages
        copy[index].content = context + "\n\nQuestion: " + copy[index].content
        return copy
    }
}

/// What the chat needs to search for a model without tools: is web search on for this kind of model, and run one.
struct PreSearcher: Sendable {
    var isOn: @MainActor @Sendable (ModelSource) -> Bool
    /// The answer of the search tool, or nil when nothing could run (switched off, no tool, a refused first-use note).
    var search: @MainActor @Sendable (_ query: String, _ context: ToolContext) async -> ToolResult?

    static let none = PreSearcher(isOn: { _ in false }, search: { _, _ in nil })
}
