import Foundation

/// When a paste is worth offering presets for, and what a preset does to the pasted text. No UI, so it is tested directly.
enum PasteOfferLogic {
    /// A change to the composer that adds at least this many characters at once is a paste. Typing, autocorrect and
    /// predictive text add a word at a time.
    static let minInserted = 24

    /// The block that appeared between two values of the composer, or nil when the change is not a paste: it must only
    /// insert (nothing replaced or deleted), at least `minInserted` characters, not just whitespace.
    static func pastedText(from old: String, to new: String) -> String? {
        let before = Array(old), after = Array(new)
        guard after.count - before.count >= minInserted else { return nil }
        var head = 0
        while head < before.count, before[head] == after[head] { head += 1 }
        var tail = 0
        while tail < before.count - head, before[before.count - 1 - tail] == after[after.count - 1 - tail] { tail += 1 }
        guard head + tail == before.count else { return nil }
        let inserted = String(after[head..<(after.count - tail)])
        guard inserted.trimmingCharacters(in: .whitespacesAndNewlines).count >= minInserted else { return nil }
        return inserted
    }

    /// The composer text after a preset is applied to what was pasted: the prompt, then the text.
    static func apply(_ preset: PromptPreset, to input: String) -> String {
        InboundChatLogic.composerText(preset: preset, text: input)
    }

    /// A preset whose prompt ends in a line break ("Text:\n") expects the text right after it. Settings lists these first.
    static func takesText(_ preset: PromptPreset) -> Bool { preset.prompt.hasSuffix("\n") }
}
