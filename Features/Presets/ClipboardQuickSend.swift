import Foundation
import NaturalLanguage

/// The message a quick action sends for a copied text: the preset's prompt, then the text. Translate goes into the
/// device language, or into English when the text is already in the device language. Other pickers keep their first choice.
enum ClipboardQuickSend {
    static func prompt(_ preset: PromptPreset, text: String, deviceLanguage: String) -> String? {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return nil }
        var selection = PresetSelection()
        if preset.id == "translate", let option = preset.options?.first(where: { $0.id == "language" }),
           let choice = targetLanguage(for: body, choices: option.choices, deviceLanguage: deviceLanguage) {
            selection.pick(choice.id, for: option)
        }
        return PresetOptionsLogic.composerText(preset, selection: selection, message: body)
    }

    /// The choice for the device language, or for English when the text is already in it. Nil when the preset offers
    /// neither, and the first choice then stands.
    static func targetLanguage(for text: String, choices: [PresetOption.Choice], deviceLanguage: String) -> PresetOption.Choice? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        let wanted = recognizer.dominantLanguage?.rawValue == deviceLanguage ? "en" : deviceLanguage
        guard let name = Locale(identifier: "en_US").localizedString(forLanguageCode: wanted) else { return nil }
        return choices.first { $0.wording.caseInsensitiveCompare(name) == .orderedSame }
    }
}
