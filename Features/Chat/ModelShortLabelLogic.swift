import Foundation

/// A model name short enough for the quiet line under a reply: "Gemma 4 E2B", "Haiku 4.5", "Apple".
/// Pure, so the names of the real catalog are tested.
enum ModelShortLabel {
    /// A label longer than this loses its trailing size and variant words, down to two words.
    static let maxLength = 14

    /// Makers whose name only repeats in front of the model's own: "Google Gemma 3" reads "Gemma 3".
    private static let makers: Set<String> = ["google", "openai", "anthropic", "meta", "nvidia", "microsoft"]

    static func make(_ name: String) -> String {
        var text = name
        // A quantization or alias in brackets is detail, not the name: "Gemma 4 E2B (Q4_0 (QAT))".
        if let bracket = text.range(of: " (") { text = String(text[..<bracket.lowerBound]) }
        var words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        if words.first?.lowercased() == "apple" { return "Apple" }
        // "Anthropic: Claude Haiku 4.5", the way some model lists write a maker.
        if words.count > 1, words[0].hasSuffix(":") { words.removeFirst() }
        if words.count > 1, makers.contains(words[0].lowercased()) { words.removeFirst() }
        if words.count > 1, words[0].lowercased() == "claude" { words.removeFirst() }
        while words.count > 2, words.joined(separator: " ").count > maxLength { words.removeLast() }
        return words.joined(separator: " ")
    }
}
