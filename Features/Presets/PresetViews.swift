import SwiftUI

/// Empty-chat starters as one scrolling row of chips just above the composer, plus Shuffle.
/// Tap fills the composer; long-press offers "Send now". Categories live in the presets sheet.
struct PresetSuggestions: View {
    let store: PresetStore
    var onPick: (PromptPreset) -> Void
    var onSend: (PromptPreset) -> Void

    @State private var salt: UInt64 = 0

    private var items: [PromptPreset] {
        PresetLogic.featured(store.all, customIDs: store.customIDs, category: nil,
                             seed: PresetLogic.daySeed(for: .now) &+ salt, limit: 8)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                Button { salt &+= 1 } label: {
                    Image(systemName: "shuffle")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(ARHomePalette.secondaryText)
                        .frame(width: 40, height: 52)
                        .background(ARColor.card.opacity(0.7), in: Capsule())
                        .overlay(Capsule().strokeBorder(ARColor.border, lineWidth: 1))
                }
                .accessibilityLabel("Shuffle presets")
                ForEach(items) { chip(\$0) }
            }
            .padding(.horizontal, ARTheme.pagePadding)
        }
    }

    private func chip(_ preset: PromptPreset) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(preset.title).font(.arSM.weight(.semibold)).foregroundStyle(ARColor.foreground).lineLimit(1)
            Text(preset.prompt).font(.arXS).foregroundStyle(ARHomePalette.secondaryText).lineLimit(1)
        }
        .frame(width: 190, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(ARColor.card.opacity(0.7), in: RoundedRectangle(cornerRadius: ARTheme.radiusLarge, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: ARTheme.radiusLarge, style: .continuous).strokeBorder(ARColor.border, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { onPick(preset) }
        .contextMenu {
            Button("Send now", systemImage: "arrow.up.circle") { onSend(preset) }
            Button("Edit in composer", systemImage: "square.and.pencil") { onPick(preset) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

struct PresetCard: View {
    let preset: PromptPreset

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: preset.symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(ARColor.mutedForeground)
            Text(preset.title).font(.arSM.weight(.medium)).foregroundStyle(ARColor.foreground).lineLimit(1)
            Text(preset.prompt).font(.arXS).foregroundStyle(ARColor.mutedForeground).lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .padding(12)
        .arCard(radius: ARTheme.radiusLarge)
        .contentShape(Rectangle())
    }
}

private struct CategoryChip: View {
    let title: String
    let selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.arSM)
                .foregroundStyle(selected ? ARColor.primaryForeground : ARColor.foreground)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(selected ? ARColor.primary : ARColor.input.opacity(0.5), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// All presets with search and categories, opened from the composer's sparkles button.
struct PresetSheet: View {
    let store: PresetStore
    var onPick: (PromptPreset) -> Void
    var onSend: (PromptPreset) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var category: PromptPreset.Category?

    private var results: [PromptPreset] { PresetLogic.filter(store.all, category: category, query: query) }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Presets").font(.arXL).foregroundStyle(ARColor.foreground)
                Spacer()
                Button("Done") { dismiss() }
            }
            ARSearchField(text: $query, prompt: "Search presets")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    CategoryChip(title: "All", selected: category == nil) { category = nil }
                    ForEach(PromptPreset.Category.allCases) { value in
                        CategoryChip(title: value.title, selected: category == value) { category = value }
                    }
                }
            }
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(results) { preset in
                        PresetCard(preset: preset)
                            .onTapGesture { onPick(preset); dismiss() }
                            .contextMenu {
                                Button("Send now", systemImage: "arrow.up.circle") { onSend(preset); dismiss() }
                            }
                            .accessibilityAddTraits(.isButton)
                    }
                    if results.isEmpty {
                        Text("No presets match.").font(.arSM).foregroundStyle(ARColor.mutedForeground).padding(.top, 24)
                    }
                }
            }
        }
        .padding(ARTheme.pagePadding)
    }
}

/// Settings: add, edit and delete your own presets; hide or restore built-ins.
struct PresetsSettingsSheet: View {
    let store: PresetStore
    @Environment(\.dismiss) private var dismiss
    @State private var editing: PromptPreset?
    @State private var creating = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    if let error = store.saveError { ErrorBanner(text: error) {} }
                    SettingsGroup("Your presets") {
                        if store.custom.isEmpty { SettingsText("Presets you add appear first in the chat.") }
                        ForEach(store.custom) { preset in
                            HStack {
                                Button { editing = preset } label: {
                                    Label(preset.title, systemImage: preset.symbol)
                                        .font(.arBase).foregroundStyle(ARColor.foreground)
                                }
                                Spacer()
                                Button(role: .destructive) { store.delete(id: preset.id) } label: {
                                    Image(systemName: "trash")
                                }
                                .accessibilityLabel("Delete \(preset.title)")
                            }
                        }
                        Button("Add preset") { creating = true }.buttonStyle(.arSecondary)
                    }
                    SettingsGroup("Built-in presets") {
                        ForEach(store.builtIns) { preset in
                            Toggle(isOn: Binding(
                                get: { !store.hiddenBuiltIns.contains(preset.id) },
                                set: { store.setBuiltInHidden(preset.id, hidden: !$0) }
                            )) {
                                Label(preset.title, systemImage: preset.symbol).font(.arBase).foregroundStyle(ARColor.foreground)
                            }
                        }
                        if store.hasHiddenBuiltIns {
                            Button("Show all built-ins") { store.resetBuiltIns() }.buttonStyle(.arSecondary)
                        }
                    }
                }
                .frame(maxWidth: ARTheme.contentMaxWidth)
                .padding(.horizontal, ARTheme.pagePadding)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity)
            }
        }
        .sheet(isPresented: $creating) { PresetEditor(store: store, preset: nil) }
        .sheet(item: $editing) { PresetEditor(store: store, preset: $0) }
    }
}

private struct PresetEditor: View {
    let store: PresetStore
    let preset: PromptPreset?
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var prompt = ""
    @State private var category: PromptPreset.Category = .explore

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Save") { save() }.disabled(!canSave)
            }
            TextField("Title", text: $title)
                .padding(10)
                .background(ARColor.input.opacity(0.5), in: RoundedRectangle(cornerRadius: ARTheme.radius, style: .continuous))
            Picker("Category", selection: $category) {
                ForEach(PromptPreset.Category.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            TextField("Prompt", text: $prompt, axis: .vertical)
                .lineLimit(4...12)
                .padding(10)
                .background(ARColor.input.opacity(0.5), in: RoundedRectangle(cornerRadius: ARTheme.radius, style: .continuous))
            Spacer()
        }
        .padding(ARTheme.pagePadding)
        .onAppear {
            guard let preset else { return }
            title = preset.title
            prompt = preset.prompt
            category = preset.category
        }
    }

    private func save() {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if var preset {
            preset.title = title
            preset.prompt = prompt
            preset.category = category
            store.update(preset)
        } else {
            store.add(title: title, prompt: prompt, category: category)
        }
        dismiss()
    }
}
