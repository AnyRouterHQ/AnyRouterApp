import Foundation

extension ChatViewModel {
    /// The row above the composer for the chat as it is now. `clipboardOffered`, `isDictating` and `mentionPanelOpen`
    /// live outside the view model, so the composer passes them in.
    func suggestions(presets: PresetStore, clipboardOffered: Bool, isDictating: Bool, mentionPanelOpen: Bool) -> ComposerSuggestions? {
        let state = ComposerSuggestionState(
            chatHasMessages: !messages.isEmpty, inputIsEmpty: input.isEmpty, clipboardOffered: clipboardOffered,
            pasteOffered: pasteOffered, isDictating: isDictating, mentionPanelOpen: mentionPanelOpen)
        return ComposerSuggestionLogic.visible(
            state, textPresets: presets.pasteOffered,
            starters: PresetLogic.featured(presets.all, customIDs: presets.customIDs, category: nil,
                                           seed: PresetLogic.daySeed(for: .now), limit: .max))
    }

    /// A preset chip was tapped. `clipboardText` is read by the caller, in the person's own tap, only for `.clipboard`.
    @discardableResult
    func choose(_ preset: PromptPreset, mode: ComposerSuggestionMode, clipboardText: () -> String) -> Task<Void, Never>? {
        switch mode {
        case .starters:
            usePreset(preset)
            return nil
        case .clipboard:
            return useClipboard(preset, text: clipboardText())
        case .pasted:
            applyToPaste(preset)
            return nil
        }
    }
}
