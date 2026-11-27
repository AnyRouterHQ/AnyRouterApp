import Foundation

/// The user's picks for a preset's options: option id to choice id. An option with no pick uses its first choice.
struct PresetSelection: Equatable, Sendable {
    private var picks: [String: String] = [:]

    func choice(for option: PresetOption) -> PresetOption.Choice {
        if let chosen = option.choices.first(where: { $0.id == picks[option.id] }) { return chosen }
        return option.choices[0]
    }

    mutating func pick(_ choiceID: String, for option: PresetOption) {
        picks[option.id] = choiceID
    }
}

extension PromptPreset {
    /// The preset asks for choices (a tone, a language) before it runs.
    var hasOptions: Bool { options?.isEmpty == false }

    /// The prompt with every option at its default.
    var resolvedPrompt: String { PresetOptionsLogic.prompt(self, selection: PresetSelection()) }
}

enum PresetOptionsLogic {
    /// The prompt with each `{option}` replaced by the wording of the picked choice.
    static func prompt(_ preset: PromptPreset, selection: PresetSelection) -> String {
        guard let options = preset.options else { return preset.prompt }
        return options.reduce(preset.prompt) { text, option in
            text.replacingOccurrences(of: "{\(option.id)}", with: selection.choice(for: option).wording)
        }
    }

    /// What goes into the composer: the prompt for these picks, then the message to answer.
    static func composerText(_ preset: PromptPreset, selection: PresetSelection, message: String) -> String {
        var resolved = preset
        resolved.prompt = prompt(preset, selection: selection)
        resolved.options = nil
        return InboundChatLogic.composerText(preset: resolved, text: message)
    }

    /// A line for a chip or a list row: the option names when there are pickers, else the prompt.
    static func summary(_ preset: PromptPreset) -> String {
        if let action = preset.action { return action.summary }
        guard let options = preset.options, !options.isEmpty else { return preset.prompt }
        return "Choose " + options.map { $0.title.lowercased() }.joined(separator: " and ")
    }
}
