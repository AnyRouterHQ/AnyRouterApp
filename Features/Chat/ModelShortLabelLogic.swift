import Foundation

/// A model name short enough for the quiet line under a reply: "Gemma 4 E2B", "Haiku 4.5", "Apple".
/// Pure, so the names of the real catalog are tested.
enum ModelShortLabel {
    /// A label longer than this loses its trailing size and variant words, down to two words.
    static let maxLength = 14

    /// Makers whose name only repeats in front of the model's own: "Google Gemma 3" reads "Gemma 3".
    private static let makers: Set<String> = ["google", "openai", "anthropic", "meta", "nvidia", "microsoft"]

    /// The name a model goes by everywhere: picker rows, the chat header, reply footers, switch notes, Local Models.
    /// An on-device model drops the quantization its catalog name carries in brackets ("Gemma 4 E2B (Q4_0 (QAT))" is
    /// "Gemma 4 E2B"); the auto router is "AnyRouter"; every other model keeps its name.
    static func name(of model: ModelDescriptor) -> String {
        if model.id == ModelDescriptor.autoRouterID { return "AnyRouter" }
        guard model.source == .gguf || model.source == .mlx, let bracket = model.displayName.range(of: " (") else {
            return model.displayName
        }
        return String(model.displayName[..<bracket.lowerBound])
    }

    /// An on-device model's variant for the second line of its row: the bracket of its catalog name without the
    /// nested brackets ("Q4_0 QAT"), else the format read from its file ("GGUF Q4_K_M", "MLX 4-bit"). Nil otherwise.
    static func variant(of model: ModelDescriptor) -> String? {
        guard model.source == .gguf || model.source == .mlx else { return nil }
        if let bracket = model.displayName.range(of: " (") {
            let inner = String(model.displayName[bracket.upperBound...].filter { $0 != "(" && $0 != ")" })
            let text = inner.trimmingCharacters(in: .whitespaces)
            if !text.isEmpty { return text }
        }
        return PickerRow.format(model)
    }

    static func make(_ name: String) -> String {
        var text = name
        // A quantization or alias in brackets is detail, not the name: "Gemma 4 E2B (Q4_0 (QAT))".
        if let bracket = text.range(of: " (") { text = String(text[..<bracket.lowerBound]) }
        var words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        if words.first?.lowercased() == "apple" { return name.hasSuffix("(Cloud)") ? "Apple Cloud" : "Apple" }
        // "Anthropic: Claude Haiku 4.5", the way some model lists write a maker.
        if words.count > 1, words[0].hasSuffix(":") { words.removeFirst() }
        if words.count > 1, makers.contains(words[0].lowercased()) { words.removeFirst() }
        if words.count > 1, words[0].lowercased() == "claude" { words.removeFirst() }
        while words.count > 2, words.joined(separator: " ").count > maxLength { words.removeLast() }
        return words.joined(separator: " ")
    }
}
