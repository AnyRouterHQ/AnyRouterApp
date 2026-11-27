import Foundation

/// One chip in the row above the composer.
enum ComposerSuggestion: Identifiable, Equatable, Sendable {
    /// What was copied, named by kind ("Copied text"). Tapping it puts the copy in the composer to edit first.
    case clipboard(ClipboardKind)
    case preset(PromptPreset)
    /// A menu with every preset and a way to edit them.
    case more

    var id: String {
        switch self {
        case .clipboard: "clipboard"
        case .preset(let preset): "preset.\(preset.id)"
        case .more: "more"
        }
    }
}

/// What a preset chip does when it is tapped, which depends on why the row is showing.
enum ComposerSuggestionMode: Equatable, Sendable {
    /// An empty chat: the preset prompt goes into the composer.
    case starters
    /// Something was copied elsewhere: a tap on a preset reads it and sends at once.
    case clipboard
    /// A block was just pasted into the composer: the preset is applied to it.
    case pasted
}

/// The row to show, or nothing.
struct ComposerSuggestions: Equatable, Sendable {
    var mode: ComposerSuggestionMode
    var items: [ComposerSuggestion]
}

/// Everything that decides whether the row shows.
struct ComposerSuggestionState: Equatable, Sendable {
    var chatHasMessages: Bool
    var inputIsEmpty: Bool
    /// What was copied since the clipboard was last offered, or nil (see `ClipboardLauncher`).
    var clipboardKind: ClipboardKind?
    /// A block was pasted into the composer and has not been edited since (see `ChatViewModel.pasteOffered`).
    var pasteOffered: Bool
    var isDictating: Bool
    /// The @ list is open.
    var mentionPanelOpen: Bool
}

/// The one place that decides what appears above the composer. No UI, so it is tested directly.
enum ComposerSuggestionLogic {
    /// Preset chips in the row. The rest are in the More menu.
    static let maxPresets = 4

    /// Rules, first match wins:
    /// - nothing while dictating or while the @ list is open;
    /// - a fresh paste in the composer: the text presets, to apply to that text;
    /// - nothing while the composer has text;
    /// - a copy waiting: its chip first, then the quick actions for that kind (`clipboardPresetIDs`);
    /// - an empty chat: the starter presets;
    /// - nothing in a chat that already has messages.
    ///
    /// `textPresets` are the ones that work on text, `starters` the presets in the order an empty chat offers them,
    /// `clipboardPresets` the quick actions for the copied kind.
    static func visible(
        _ state: ComposerSuggestionState, textPresets: [PromptPreset], starters: [PromptPreset], clipboardPresets: [PromptPreset] = []
    ) -> ComposerSuggestions? {
        guard !state.isDictating, !state.mentionPanelOpen else { return nil }
        if state.pasteOffered, !state.inputIsEmpty {
            return chips(.pasted, leading: [], presets: textPresets)
        }
        guard state.inputIsEmpty else { return nil }
        if let kind = state.clipboardKind {
            return chips(.clipboard, leading: [.clipboard(kind)], presets: clipboardPresets)
        }
        guard !state.chatHasMessages else { return nil }
        return chips(.starters, leading: [], presets: starters)
    }

    /// The quick actions offered for a copy, by preset id, in order. A hidden preset is simply left out.
    static func clipboardPresetIDs(_ kind: ClipboardKind) -> [String] {
        switch kind {
        case .text: ["fix-english", "summarize", "translate", "reply-to-this"]
        case .link: ["summarize-link", "key-points"]
        case .image: ["describe-image", "read-photo"]
        }
    }

    private static func chips(_ mode: ComposerSuggestionMode, leading: [ComposerSuggestion], presets: [PromptPreset]) -> ComposerSuggestions? {
        let shown = presets.prefix(maxPresets).map(ComposerSuggestion.preset)
        // More is there whenever a preset is: it lists every preset, not just the ones that did not fit.
        let items = leading + shown + (shown.isEmpty ? [] : [.more])
        return items.isEmpty ? nil : ComposerSuggestions(mode: mode, items: items)
    }
}
