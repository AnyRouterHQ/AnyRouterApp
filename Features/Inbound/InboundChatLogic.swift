import Foundation

enum InboundChatLogic {
    /// The composer text for a request. A preset prompt that ends in a line break ("Email:\n") takes the text right
    /// after it; any other preset prompt gets a blank line first, so the text reads as extra context.
    static func composerText(preset: PromptPreset?, text: String?) -> String {
        let body = trimmed(text)
        guard let preset else { return body }
        let prompt = preset.resolvedPrompt
        if body.isEmpty { return prompt }
        let lead = prompt.hasSuffix("\n") ? prompt : prompt + "\n\n"
        return lead + body
    }

    private static func trimmed(_ text: String?) -> String {
        guard let text else { return "" }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
