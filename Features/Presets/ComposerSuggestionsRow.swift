import SwiftUI

/// The one row above the composer: on an empty chat, two-line starter cards; for a copy or a paste, one-line chips.
/// Both are glass like the controls beside the field, and a More menu ends the row. What shows, and in what order, is
/// decided by `ComposerSuggestionLogic`.
struct ComposerSuggestionsRow: View {
    let suggestions: ComposerSuggestions
    let presets: PresetStore
    var onClipboard: (ClipboardKind) -> Void
    var onPreset: (PromptPreset) -> Void
    var onSend: (PromptPreset) -> Void
    var onEditPresets: () -> Void
    var onDismiss: () -> Void
    @ScaledMetric(relativeTo: .subheadline) private var cardRadius: CGFloat = 18

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(suggestions.items) { item in
                    switch item {
                    case .clipboard(let kind): clipboardChip(kind)
                    case .preset(let preset):
                        if suggestions.mode == .starters { starterCard(preset) } else { presetChip(preset) }
                    case .more: moreMenu
                    }
                }
                // Starters belong to the empty chat and go away on their own. A clipboard or paste offer can be waved off.
                if suggestions.mode != .starters {
                    Button(role: .close, action: onDismiss)
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityLabel("Hide suggestions")
                        .accessibilityIdentifier("composer.suggestion.hide")
                }
            }
        }
        // The first chip starts at the screen margin, the edge of the + button; the row scrolls out past the trailing edge.
        .scrollClipDisabled()
        .accessibilityIdentifier("composer.suggestions")
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
        .chipOutline(.capsule)
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
        .chipOutline(.capsule)
        .frame(minHeight: 44)
        .accessibilityIdentifier("composer.suggestion.preset.\(preset.id)")
    }

    /// A starter on the empty chat: the title in bold over a line that reads on from it. A tap fills the composer; the
    /// context menu sends it at once.
    private func starterCard(_ preset: PromptPreset) -> some View {
        Button { onPreset(preset) } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(preset.title).font(.subheadline.weight(.semibold))
                Text(preset.cardDetail).font(.subheadline).foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .padding(.vertical, 4)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.roundedRectangle(radius: cardRadius))
        .controlSize(.regular)
        .chipOutline(.rect(cornerRadius: cardRadius))
        .contextMenu {
            if preset.action == nil {
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
            Label("More presets", systemImage: "ellipsis").labelStyle(.iconOnly)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .controlSize(.regular)
        .chipOutline(.circle)
        .frame(minWidth: 44, minHeight: 44)
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

private extension View {
    /// A hairline around a chip. Clear glass on a white screen has no edge of its own in light mode.
    func chipOutline(_ shape: some InsettableShape) -> some View {
        overlay(shape.strokeBorder(Color(.separator), lineWidth: 0.5).allowsHitTesting(false))
    }
}
