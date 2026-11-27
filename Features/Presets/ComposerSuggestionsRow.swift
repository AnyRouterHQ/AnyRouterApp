import SwiftUI

/// The one row above the composer: the system Paste button, a few preset chips and a More menu, all one line, in
/// glass like the controls beside the field. What shows, and in what order, is decided by `ComposerSuggestionLogic`.
struct ComposerSuggestionsRow: View {
    let suggestions: ComposerSuggestions
    let presets: PresetStore
    var onPaste: (String) -> Void
    var onPreset: (PromptPreset) -> Void
    var onSend: (PromptPreset) -> Void
    var onEditPresets: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(suggestions.items) { item in
                    switch item {
                    case .paste: pasteChip
                    case .preset(let preset): presetChip(preset)
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

    private var pasteChip: some View {
        PasteButton(payloadType: String.self) { onPaste($0.joined(separator: "\n")) }
            .labelStyle(.titleAndIcon)
            .buttonBorderShape(.capsule)
            .controlSize(.regular)
            // The system picks the label color for the tint. The accent is white in dark mode, which left a white label on a light grey pill.
            .tint(Color(.systemGray5))
            .chipOutline(Capsule())
            .frame(minHeight: 44)
            .accessibilityIdentifier("composer.suggestion.paste")
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
        .chipOutline(Capsule())
        .frame(minHeight: 44)
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
            Label("More presets", systemImage: "ellipsis").labelStyle(.iconOnly)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .controlSize(.regular)
        .chipOutline(Circle())
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
    func chipOutline(_ shape: some Shape) -> some View {
        overlay(shape.strokeBorder(Color(.separator), lineWidth: 0.5).allowsHitTesting(false))
    }
}
