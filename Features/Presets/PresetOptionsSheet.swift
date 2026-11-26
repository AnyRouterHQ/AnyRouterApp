import SwiftUI

/// The choices for a preset with pickers (tone, language) and the message to answer. "Reply" sends it.
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
                Section {
                    ForEach(preset.options ?? []) { option in
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
                    .accessibilityLabel("Reply")
                    .accessibilityIdentifier("preset-options.confirm")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
