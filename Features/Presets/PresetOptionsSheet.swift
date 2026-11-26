import SwiftUI

/// One menu picker per option of a preset (tone, language, people, tip).
struct PresetOptionPickers: View {
    let options: [PresetOption]
    @Binding var selection: PresetSelection

    var body: some View {
        ForEach(options) { option in
            Picker(option.title, selection: Binding(
                get: { selection.choice(for: option).id },
                set: { selection.pick($0, for: option) }
            )) {
                ForEach(option.choices) { Text($0.title).tag($0.id) }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("preset-options.\(option.id)")
        }
    }
}

/// The choices for a preset with pickers (tone, language) and the message to answer. The confirm button sends it.
struct PresetOptionsSheet: View {
    let preset: PromptPreset
    var onConfirm: (PresetSelection, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selection = PresetSelection()
    @State private var message: String

    init(preset: PromptPreset, message: String, onConfirm: @escaping (PresetSelection, String) -> Void) {
        self.preset = preset
        self.onConfirm = onConfirm
        _message = State(initialValue: message)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Message") {
                    TextField("Paste or type the message", text: $message, axis: .vertical)
                        .lineLimit(4...12)
                        .accessibilityIdentifier("preset-options.message")
                    PasteButton(payloadType: String.self) { message = $0.joined(separator: "\n") }
                }
                if let options = preset.options {
                    Section { PresetOptionPickers(options: options, selection: $selection) }
                }
            }
            .navigationTitle(preset.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(role: .cancel) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) {
                        onConfirm(selection, message)
                        dismiss()
                    }
                    .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Send")
                    .accessibilityIdentifier("preset-options.confirm")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// The text read from a photo, editable, with what to do next: put it in the composer as it is, or with Translate,
/// Split this bill or Summarize in front of it.
struct ReadTextSheet: View {
    let presets: [PromptPreset]
    var onUse: (PromptPreset?, PresetSelection, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var presetID: String?
    @State private var selection = PresetSelection()

    init(text: String, presets: [PromptPreset], onUse: @escaping (PromptPreset?, PresetSelection, String) -> Void) {
        self.presets = presets
        self.onUse = onUse
        _text = State(initialValue: text)
    }

    private var chosen: PromptPreset? { presets.first { $0.id == presetID } }

    var body: some View {
        NavigationStack {
            Form {
                Section("Text from the photo") {
                    TextField("Text", text: $text, axis: .vertical)
                        .lineLimit(6...16)
                        .accessibilityIdentifier("read-text.text")
                }
                Section("Then") {
                    Picker("Then", selection: $presetID) {
                        Text("Just the text").tag(String?.none)
                        ForEach(presets) { preset in
                            Label(preset.title, systemImage: preset.symbol).tag(String?.some(preset.id))
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    .accessibilityIdentifier("read-text.preset")
                }
                if let options = chosen?.options {
                    Section { PresetOptionPickers(options: options, selection: $selection) }
                }
            }
            .onChange(of: presetID) { selection = PresetSelection() }
            .navigationTitle("Read text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(role: .cancel) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) {
                        onUse(chosen, selection, text)
                        dismiss()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Use")
                    .accessibilityIdentifier("read-text.confirm")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
