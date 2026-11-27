import Foundation

extension ChatViewModel {
    /// The row above the composer for the chat as it is now. `clipboardKind`, `isDictating` and `mentionPanelOpen`
    /// live outside the view model, so the composer passes them in.
    func suggestions(presets: PresetStore, clipboardKind: ClipboardKind?, isDictating: Bool, mentionPanelOpen: Bool) -> ComposerSuggestions? {
        let state = ComposerSuggestionState(
            chatHasMessages: !messages.isEmpty, inputIsEmpty: input.isEmpty, clipboardKind: clipboardKind,
            pasteOffered: pasteOffered, isDictating: isDictating, mentionPanelOpen: mentionPanelOpen)
        return ComposerSuggestionLogic.visible(
            state, textPresets: presets.pasteOffered,
            starters: PresetLogic.featured(presets.all, customIDs: presets.customIDs, category: nil,
                                           seed: PresetLogic.daySeed(for: .now), limit: .max),
            clipboardPresets: clipboardKind.map { kind in
                ComposerSuggestionLogic.clipboardPresetIDs(kind).compactMap { id in presets.all.first { $0.id == id } }
            } ?? [])
    }

    /// A phone use case that only needs the text on the clipboard. `readPhoto` and `goOffline` open a picker or a
    /// dialog, so the composer runs them. The clipboard is read here, in the person's own tap.
    @discardableResult
    func run(_ action: PresetAction, clipboardText: () -> String) -> Task<Void, Never>? {
        switch action {
        case .askClipboard:
            if let text = UseCaseLogic.clipboardQuestion(clipboardText()) { fill(text) } else { showError("Nothing copied yet.") }
            return nil
        case .summarizeLink:
            let request = UseCaseLogic.linkRequest(clipboardText())
            fill(request.text)
            guard request.isReady else { return nil }
            guard supportsTools else {
                showError(UseCaseLogic.cannotOpenLinks(model?.shortName ?? "This model"))
                return nil
            }
            return send()
        case .readPhoto, .goOffline:
            return nil
        }
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
