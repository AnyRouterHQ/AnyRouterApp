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
    /// Two-line cards on an empty chat; one-line chips once the chat has messages or for a paste.
    var cards: Bool
}

/// Everything that decides whether the row shows.
struct ComposerSuggestionState: Equatable, Sendable {
    var chatHasMessages: Bool
    var inputIsEmpty: Bool
    /// What was copied since the clipboard was last offered, or nil: its chip leads the row (see `ClipboardLauncher`).
    var clipboardKind: ClipboardKind?
    /// What is on the clipboard now, known without reading it, or nil when it is empty or was waved off. It picks the
    /// empty chat's cards.
    var clipboardContent: ClipboardKind?
    /// A block was pasted into the composer and has not been edited since (see `ChatViewModel.pasteOffered`).
    var pasteOffered: Bool
    var isDictating: Bool
    /// The @ list is open.
    var mentionPanelOpen: Bool
    /// The model can call tools (the clock, the page reader).
    var supportsTools: Bool
    /// The model can see photos.
    var supportsVision: Bool
}

/// The one place that decides what appears above the composer. No UI, so it is tested directly.
enum ComposerSuggestionLogic {
    /// Preset chips in the row. The rest are in the More menu.
    static let maxPresets = 4

    /// Rules, first match wins:
    /// - nothing while dictating or while the @ list is open;
    /// - a fresh paste in the composer: the text presets, to apply to that text;
    /// - nothing while the composer has text;
    /// - a chat with messages: the waiting copy's chip and its quick actions as chips, else nothing;
    /// - an empty chat: the waiting copy's chip, then cards for what is on the clipboard (`clipboardPresetIDs`), or the
    ///   person's own presets and the general starters (`starterPresetIDs`) when nothing useful is there.
    ///
    /// `presets` are the visible ones (the person's first, `customIDs`), `textPresets` the ones offered on a paste.
    static func visible(
        _ state: ComposerSuggestionState, presets: [PromptPreset], customIDs: Set<String>, textPresets: [PromptPreset]
    ) -> ComposerSuggestions? {
        guard !state.isDictating, !state.mentionPanelOpen else { return nil }
        if state.pasteOffered, !state.inputIsEmpty {
            return row(.pasted, cards: false, leading: [], presets: textPresets)
        }
        guard state.inputIsEmpty else { return nil }
        let chip = state.clipboardKind.map { [ComposerSuggestion.clipboard($0)] } ?? []
        if state.chatHasMessages {
            guard let kind = state.clipboardKind else { return nil }
            return row(.clipboard, cards: false, leading: chip, presets: pick(quickActions(kind, state), from: presets))
        }
        let onClipboard = (state.clipboardContent ?? state.clipboardKind).map { quickActions($0, state) } ?? []
        if !onClipboard.isEmpty {
            return row(.clipboard, cards: true, leading: chip, presets: pick(onClipboard, from: presets))
        }
        let starters = presets.filter { customIDs.contains($0.id) }
            + pick(starterPresetIDs(tools: state.supportsTools, vision: state.supportsVision), from: presets)
        return row(.starters, cards: true, leading: chip, presets: starters)
    }

    /// The quick actions for what was copied, by preset id, in order. A link needs tools to open the page, a picture a
    /// model that sees it; reading the text in a picture runs on the device. Empty when nothing fits.
    static func clipboardPresetIDs(_ kind: ClipboardKind, tools: Bool, vision: Bool) -> [String] {
        switch kind {
        case .text: ["fix-english", "explain-text", "translate", "summarize", "reply-to-this"]
        case .link: tools ? ["summarize-link", "about-link"] : []
        case .image: vision ? ["describe-image", "read-photo"] : ["read-photo"]
        }
    }

    /// The empty chat's starters when the clipboard has nothing to act on: each works right away. The clock needs tools,
    /// a photo question a model that sees it.
    static func starterPresetIDs(tools: Bool, vision: Bool) -> [String] {
        (tools ? ["what-time"] : []) + ["plan-day", "write-message"] + (vision ? ["ask-photo"] : []) + ["explain-simply", "what-can-you-do"]
    }

    /// Whether a tap on this preset acts on the copy. A pick from More that is not one of the copy's actions (a plan, a
    /// phone use case) runs as usual and never reads the clipboard.
    static func actsOnClipboard(_ preset: PromptPreset, kind: ClipboardKind, tools: Bool, vision: Bool) -> Bool {
        clipboardPresetIDs(kind, tools: tools, vision: vision).contains(preset.id)
    }

    private static func quickActions(_ kind: ClipboardKind, _ state: ComposerSuggestionState) -> [String] {
        clipboardPresetIDs(kind, tools: state.supportsTools, vision: state.supportsVision)
    }

    /// The presets with these ids, in this order. A hidden preset is simply left out.
    private static func pick(_ ids: [String], from presets: [PromptPreset]) -> [PromptPreset] {
        ids.compactMap { id in presets.first { $0.id == id } }
    }

    private static func row(
        _ mode: ComposerSuggestionMode, cards: Bool, leading: [ComposerSuggestion], presets: [PromptPreset]
    ) -> ComposerSuggestions? {
        let shown = presets.prefix(maxPresets).map(ComposerSuggestion.preset)
        // More is there whenever a preset is: it lists every preset, not just the ones that did not fit.
        let items = leading + shown + (shown.isEmpty ? [] : [.more])
        return items.isEmpty ? nil : ComposerSuggestions(mode: mode, items: items, cards: cards)
    }
}
