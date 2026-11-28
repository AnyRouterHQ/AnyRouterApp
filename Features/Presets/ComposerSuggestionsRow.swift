import SwiftUI

/// The one row above the composer: on an empty chat, two-line cards; in a chat with messages or for a paste, one-line chips.
/// Both are glass like the controls beside the field. The chips scroll under the More menu, which floats at the end of
/// the row, in view. What shows, and in what order, is decided by `ComposerSuggestionLogic`.
struct ComposerSuggestionsRow: View {
    let suggestions: ComposerSuggestions
    let presets: PresetStore
    var onClipboard: (ClipboardKind) -> Void
    var onPreset: (PromptPreset) -> Void
    var onSend: (PromptPreset) -> Void
    var onEditPresets: () -> Void
    @ScaledMetric(relativeTo: .subheadline) private var moreSide: CGFloat = 44
    // One label height and one symbol box for every chip: symbols differ in height and glass sizes itself to its label,
    // so without these the pills come out at different heights. Scaled so they still follow Dynamic Type.
    @ScaledMetric(relativeTo: .subheadline) private var chipLabelHeight: CGFloat = 24
    @ScaledMetric(relativeTo: .subheadline) private var chipSymbolSide: CGFloat = 20
    @ScaledMetric(relativeTo: .subheadline) private var cardLabelHeight: CGFloat = 40

    var body: some View {
        let hasMore = suggestions.items.contains(.more)
        ScrollView(.horizontal, showsIndicators: false) {
            // The chips' own glass container: the scroll view sits between them and the composer's.
            GlassEffectContainer(spacing: 4) {
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
        }
        // From the screen's leading edge, with the first chip on the page margin (the edge of the + button). At the
        // trailing end the cards pass under the floating More instead of being cut hard against it, and the last card
        // can scroll fully clear of it.
        .contentMargins(.leading, ARTheme.pagePadding, for: .scrollContent)
        .contentMargins(.trailing, hasMore ? moreSide + 8 : 0, for: .scrollContent)
        .padding(.leading, -ARTheme.pagePadding)
        // The row's own scroll edge effects drew a grey box the size of the row behind the cards (design review P1,
        // screenshots 46140428971 on iPad); the chat list's edge effect is the one this bar needs.
        .scrollEdgeEffectHidden(true, for: .all)
        // On the scroll view, not the HStack: an HStack would hand this id down to every chip.
        .accessibilityIdentifier("composer.suggestions")
        // Floating over the scroll, so More (and its Edit Presets…) is reachable without scrolling past every card.
        // The one trailing control: typing or a new chat clears a clipboard or paste offer, so it needs no Hide.
        .overlay(alignment: .trailing) {
            if hasMore { moreMenu }
        }
    }

    /// What was copied, by kind, in the same glass as the presets. Tapping it puts the copy in the composer.
    private func clipboardChip(_ kind: ClipboardKind) -> some View {
        Button { onClipboard(kind) } label: {
            chipLabel(kind.title, kind.symbol)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
        .controlSize(.regular)
        .frame(minHeight: 44)
        .accessibilityHint("Puts it in the message to edit")
        .accessibilityIdentifier("composer.suggestion.clipboard")
    }

    /// Single line, one symbol box, one minimum height: the same size whatever the label or symbol.
    private func chipLabel(_ title: String, _ symbol: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .frame(width: chipSymbolSide, height: chipSymbolSide)
            Text(title)
        }
        .font(.subheadline)
        .lineLimit(1)
        .truncationMode(.tail)
        .fixedSize(horizontal: false, vertical: true)
        .frame(minHeight: chipLabelHeight)
    }

    private func presetChip(_ preset: PromptPreset) -> some View {
        Button { onPreset(preset) } label: {
            chipLabel(preset.title, preset.symbol)
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
            .truncationMode(.tail)
            .fixedSize(horizontal: false, vertical: true)
            .frame(minHeight: cardLabelHeight)
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
            Label("More presets", systemImage: "ellipsis")
                .labelStyle(.iconOnly)
                .foregroundStyle(.primary)
                .glassCircle(diameter: moreSide)
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
