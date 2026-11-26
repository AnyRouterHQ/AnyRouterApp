import Foundation

/// Text a page or a search result gives the model is not the user's word, yet the model may act on it. A tool that
/// runs without asking could then send chat text to any server by putting it in a URL or a search. These rules ask
/// first in the cases that can carry data out:
///
/// - A URL goes out only unasked when its host appears in what the user wrote or attached in this chat.
///   (So fetching a link the user pasted is silent; fetching a link from a search result asks, with the full URL.)
/// - A search query that repeats a passage of 80 or more characters of the user's text asks. Ordinary searches,
///   including ones that quote a few words, stay silent.
struct ExfiltrationGuard: Sendable {
    static let verbatimLimit = 80

    private let userTexts: [String]
    private let normalizedTexts: [String]

    init(userTexts: [String]) {
        self.userTexts = userTexts
        normalizedTexts = userTexts.map(Self.normalize)
    }

    // MARK: URLs

    private static let urlPattern = try! NSRegularExpression(pattern: "https?://[^\\s\"'<>\\\\]+", options: [.caseInsensitive])

    /// Every http(s) URL inside any string of the arguments, trailing punctuation removed.
    static func urls(in value: JSONValue) -> [String] {
        switch value {
        case .string(let text):
            let range = NSRange(text.startIndex..., in: text)
            return urlPattern.matches(in: text, range: range).compactMap { match in
                Range(match.range, in: text).map { String(text[$0]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?)]}")) }
            }
        case .array(let items): return items.flatMap { urls(in: $0) }
        case .object(let fields): return fields.values.flatMap { urls(in: $0) }
        default: return []
        }
    }

    /// The URLs of the arguments whose host the user never wrote, in order and without repeats.
    func unsuppliedURLs(in arguments: JSONValue) -> [String] {
        var seen = Set<String>()
        return Self.urls(in: arguments).filter { seen.insert($0).inserted && !isSupplied($0) }
    }

    /// An unparseable URL counts as not supplied.
    func isSupplied(_ urlString: String) -> Bool {
        guard let host = URL(string: urlString)?.host()?.lowercased(), !host.isEmpty else { return false }
        let bare = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        let pattern = "(?<![A-Za-z0-9.-])(?:www\\.)?" + NSRegularExpression.escapedPattern(for: bare)
            + "(?![A-Za-z0-9-]|\\.[A-Za-z0-9])"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return false }
        return userTexts.contains { regex.firstMatch(in: $0, range: NSRange($0.startIndex..., in: $0)) != nil }
    }

    // MARK: Search text

    /// True when `query` contains a run of `verbatimLimit` characters that the user's texts contain too
    /// (compared without case and with whitespace collapsed).
    func repeatsUserText(_ query: String) -> Bool {
        let probe = Self.normalize(String(query.prefix(2_000)))
        guard probe.count >= Self.verbatimLimit else { return false }
        let characters = Array(probe)
        for start in 0...(characters.count - Self.verbatimLimit) {
            let window = String(characters[start..<(start + Self.verbatimLimit)])
            if normalizedTexts.contains(where: { $0.contains(window) }) { return true }
        }
        return false
    }

    private static func normalize(_ text: String) -> String {
        text.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
