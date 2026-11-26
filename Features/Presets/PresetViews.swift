import SwiftUI

/// Empty-chat starters as one scrolling row of buttons just above the composer, plus Shuffle.
/// Tap fills the composer; long-press offers "Send now". Categories live in the presets sheet.
struct PresetSuggestions: View {
    let store: PresetStore
    var onPick: (PromptPreset) -> Void
    var onSend: (PromptPreset) -> Void

    @State private var salt: UInt64 = 0
    /// Grows with Dynamic Type so a large text size does not truncate every chip.
    @ScaledMetric(relativeTo: .subheadline) private var chipWidth: CGFloat = 190

    private var items: [PromptPreset] {
        PresetLogic.featured(store.all, customIDs: store.customIDs, category: nil,
                             seed: PresetLogic.daySeed(for: .now) &+ salt, limit: 8)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                Button { salt &+= 1 } label: {
                    Label("Shuffle presets", systemImage: "shuffle").labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .controlSize(.large)
                ForEach(items) { chip($0) }
            }
            .padding(.horizontal, ARTheme.pagePadding)
        }
    }

    private func chip(_ preset: PromptPreset) -> some View {
        Button { onPick(preset) } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(preset.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(PresetOptionsLogic.summary(preset)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(width: chipWidth, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle(radius: ARTheme.radiusLarge))
        .controlSize(.large)
        .contextMenu {
            Button("Send now", systemImage: "arrow.up.circle") { onSend(preset) }
            Button("Edit in composer", systemImage: "square.and.pencil") { onPick(preset) }
        }
    }
}

/// All presets with search and a category filter, opened from the composer's sparkles button.
struct PresetSheet: View {
    let store: PresetStore
    var onPick: (PromptPreset) -> Void
    var onSend: (PromptPreset) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var category: PromptPreset.Category?

    private var results: [PromptPreset] { PresetLogic.filter(store.all, category: category, query: query) }

    var body: some View {
        NavigationStack {
            List(results) { preset in
                Button { onPick(preset); dismiss() } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(preset.title, systemImage: preset.symbol).font(.headline)
                        Text(PresetOptionsLogic.summary(preset)).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                .foregroundStyle(.primary)
                .contextMenu {
                    Button("Send now", systemImage: "arrow.up.circle") { onSend(preset); dismiss() }
                }
            }
            .overlay {
                if results.isEmpty { ContentUnavailableView("No presets match", systemImage: "magnifyingglass") }
            }
            .navigationTitle("Presets")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Search presets")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(role: .close) { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Picker("Category", selection: $category) {
                            Text("All").tag(PromptPreset.Category?.none)
                            ForEach(PromptPreset.Category.allCases) { value in
                                Text(value.title).tag(PromptPreset.Category?.some(value))
                            }
                        }
                    } label: {
                        Label("Category", systemImage: "line.3.horizontal.decrease")
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationSizing(.form)
    }
}

/// Settings page: add, edit and delete your own presets; hide or restore built-ins.
struct PresetsSettingsSheet: View {
    let store: PresetStore
    @State private var editing: PromptPreset?
    @State private var creating = false

    var body: some View {
        Form {
            if let error = store.saveError {
                Section { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) }
            }
            Section {
                ForEach(store.custom) { preset in
                    Button { editing = preset } label: { Label(preset.title, systemImage: preset.symbol) }
                        .foregroundStyle(.primary)
                        .swipeActions {
                            Button(role: .destructive) { store.delete(id: preset.id) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
                Button("Add preset", systemImage: "plus") { creating = true }
            } header: {
                Text("Your presets")
            } footer: {
                if store.custom.isEmpty { Text("Presets you add appear first in the chat.") }
            }
            Section {
                ForEach(store.all.filter { PasteOfferLogic.takesText($0) || store.offersOnPaste($0) }) { preset in
                    Toggle(isOn: Binding(
                        get: { store.offersOnPaste(preset) },
                        set: { store.setOffersOnPaste(preset.id, $0) }
                    )) {
                        Label(preset.title, systemImage: preset.symbol)
                    }
                }
            } header: {
                Text("Offer when pasting")
            } footer: {
                Text("When you paste text into a message, these presets appear above the keyboard. Tap one to apply it to the text.")
            }
            Section("Built-in presets") {
                ForEach(store.builtIns) { preset in
                    Toggle(isOn: Binding(
                        get: { !store.hiddenBuiltIns.contains(preset.id) },
                        set: { store.setBuiltInHidden(preset.id, hidden: !$0) }
                    )) {
                        Label(preset.title, systemImage: preset.symbol)
                    }
                }
                if store.hasHiddenBuiltIns {
                    Button("Show all built-ins") { store.resetBuiltIns() }
                }
            }
        }
        .navigationTitle("Presets")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $creating) { PresetEditor(store: store, preset: nil).presentationSizing(.form) }
        .sheet(item: $editing) { PresetEditor(store: store, preset: $0).presentationSizing(.form) }
    }
}

private struct PresetEditor: View {
    let store: PresetStore
    let preset: PromptPreset?
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var prompt = ""
    @State private var category: PromptPreset.Category = .explore
    @State private var offersOnPaste = false

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                    Picker("Category", selection: $category) {
                        ForEach(PromptPreset.Category.allCases) { Text($0.title).tag($0) }
                    }
                }
                Section("Prompt") {
                    TextField("Prompt", text: $prompt, axis: .vertical).lineLimit(4...12)
                }
                Section {
                    Toggle("Offer when pasting", isOn: $offersOnPaste)
                } footer: {
                    Text("Shown above the keyboard when you paste text into a message. The pasted text goes after the prompt.")
                }
            }
            .navigationTitle(preset == nil ? "New preset" : "Edit preset")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(role: .close) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", role: .confirm) { save() }.disabled(!canSave) }
            }
        }
        .onAppear {
            guard let preset else { return }
            title = preset.title
            prompt = preset.prompt
            category = preset.category
            offersOnPaste = preset.offerOnPaste
        }
    }

    private func save() {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if var preset {
            preset.title = title
            preset.prompt = prompt
            preset.category = category
            preset.offerOnPaste = offersOnPaste
            store.update(preset)
        } else {
            let added = store.add(title: title, prompt: prompt, category: category)
            if offersOnPaste { store.setOffersOnPaste(added.id, true) }
        }
        dismiss()
    }
}
