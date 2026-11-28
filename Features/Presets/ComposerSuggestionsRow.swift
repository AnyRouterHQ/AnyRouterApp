import SwiftUI

/// The one row above the composer: on an empty chat, two-line cards; in a chat with messages or for a paste, one-line chips.
/// Both are glass like the controls beside the field. The chips scroll; the More menu (and Hide) stay at the end of the
/// row, in view. What shows, and in what order, is decided by `ComposerSuggestionLogic`.
struct ComposerSuggestionsRow: View {
    let suggestions: ComposerSuggestions
    let presets: PresetStore
    var onClipboard: (ClipboardKind) -> Void
    var onPreset: (PromptPreset) -> Void
    var onSend: (PromptPreset) -> Void
    var onEditPresets: () -> Void
    var onDismiss: () -> Void
    @ScaledMetric(relativeTo: .subheadline) private var moreSide: CGFloat = 44

    var body: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(suggestions.items.filter { $0 != .more }) { item in
                        switch item {
                        case .clipboard(let kind): clipboardChip(kind)
                        case .preset(let preset):
                            if suggestions.cards { starterCard(preset) } else { presetChip(preset) }
                        case .more: EmptyView()
                        }
                    }
                }
            }
            // From the screen's leading edge, with the first chip on the page margin (the edge of the + button), so a card
            // cut where the row meets More says the row scrolls. No fade mask: placed after the negative padding, its frame
            // was the inset slot, so it cut the cards' shadows into a hard grey band (screenshots 46075429647).
            .contentMargins(.leading, ARTheme.pagePadding, for: .scrollContent)
            .padding(.leading, -ARTheme.pagePadding)
            // On the scroll view, not the HStack: an HStack would hand this id down to every chip.
            .accessibilityIdentifier("composer.suggestions")

            // Outside the scroll, so More (and its Edit Presets…) is reachable without scrolling past every card.
            if suggestions.items.contains(.more) { moreMenu }
            // Starters belong to the empty chat and go away on their own. A clipboard or paste offer can be waved off.
            if suggestions.mode != .starters {
                // A glyph on every device; the close role drew a "Close" text button on iPad. Glass on the label, like
                // More, so the circle is the whole 44 pt hit area.
                Button(action: onDismiss) {
                    Label("Hide suggestions", systemImage: "xmark")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.primary)
                        .frame(width: moreSide, height: moreSide)
                        .glassEffect(.regular.interactive(), in: .circle)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("composer.suggestion.hide")
            }
        }
    }

    /// What was copied, by kind, in the same glass as the presets. Tapping it puts the copy in the composer.
    private func clipboardChip(_ kind: ClipboardKind) -> some View {
        Button { onClipboard(kind) } label: {
            Label(kind.title, systemImage: kind.symbol)
                .font(.subheadline)
                .lineLimit(1)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
        .controlSize(.regular)
        .frame(minHeight: 44)
        .accessibilityHint("Puts it in the message to edit")
        .accessibilityIdentifier("composer.suggestion.clipboard")
    }

    private func presetChip(_ preset: PromptPreset) -> some View {
        Button { onPreset(preset) } label: {
            Label(preset.title, systemImage: preset.symbol)
                .font(.subheadline)
                .lineLimit(1)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
        .controlSize(.regular)
        .frame(minHeight: 44)
        .accessibilityIdentifier("composer.suggestion.preset.\(preset.id)")
    }

    /// A card on the empty chat: the title in bold over a line that reads on from it. A starter's tap fills the composer
    /// and its context menu sends it at once; a card for the clipboard acts on the copy.
    private func starterCard(_ preset: PromptPreset) -> some View {
        Button { onPreset(preset) } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(preset.title).font(.subheadline.weight(.semibold))
                // Primary, set apart by weight: secondary text on glass failed the contrast audit (verify-ui 46031167020).
                Text(preset.cardDetail).font(.subheadline)
            }
            .lineLimit(1)
            .padding(.vertical, 4)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.roundedRectangle(radius: ARTheme.radiusLarge))
        .controlSize(.regular)
        .contextMenu {
            if suggestions.mode == .starters, preset.action == nil {
                Button("Send now", systemImage: "arrow.up.circle") { onSend(preset) }
                Button("Edit in composer", systemImage: "square.and.pencil") { onPreset(preset) }
            }
        }
        .accessibilityIdentifier("composer.suggestion.preset.\(preset.id)")
    }

    /// The phone use cases, then the presets (yours first, then the built-ins by category), and the way to edit them.
    private var moreMenu: some View {
        Menu {
            let all = presets.all
            let deviceItems = all.filter(\.onDevice)
            if !deviceItems.isEmpty { section("On this device", deviceItems) }
            let others = all.filter { !$0.onDevice }
            Section("Presets") {
                let mine = others.filter { presets.customIDs.contains($0.id) }
                if !mine.isEmpty { submenu("Yours", mine) }
                ForEach(PromptPreset.Category.allCases) { category in
                    let items = others.filter { $0.category == category && !presets.customIDs.contains($0.id) }
                    if !items.isEmpty { submenu(category.title, items) }
                }
            }
            Section {
                Button("Edit Presets…", systemImage: "slider.horizontal.3", action: onEditPresets)
                    .accessibilityIdentifier("composer.suggestion.edit")
            }
        } label: {
            // Glass on the label, like the composer's +: the circle is the whole 44 pt hit area. A glass button style
            // drew a circle around the glyph only (42 × 19 pt) and an outer frame added space, not hit area.
            Label("More presets", systemImage: "ellipsis")
                .labelStyle(.iconOnly)
                .foregroundStyle(.primary)
                .frame(width: moreSide, height: moreSide)
                .glassEffect(.regular.interactive(), in: .circle)
                .contentShape(.circle)
        }
        .accessibilityIdentifier("composer.suggestion.more")
    }

    private func submenu(_ title: String, _ items: [PromptPreset]) -> some View {
        Menu(title) {
            ForEach(items) { preset in
                Button(preset.title, systemImage: preset.symbol) { onPreset(preset) }
            }
        }
    }

    private func section(_ title: String, _ items: [PromptPreset]) -> some View {
        Section(title) {
            ForEach(items) { preset in
                Button(preset.title, systemImage: preset.symbol) { onPreset(preset) }
            }
        }
    }
}
