import SwiftUI

/// The global custom instructions: one text every chat starts with. A chat can replace it from its own menu.
struct CustomInstructionsScreen: View {
    @Environment(AppSettings.self) private var settings
    @Environment(ModelStore.self) private var models

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                TextEditor(text: $settings.systemPrompt)
                    .frame(minHeight: 160)
                    .accessibilityLabel("Custom instructions")
                    .accessibilityIdentifier("instructions.editor")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(InstructionsLogic.countText(settings.systemPrompt))
                    Text(InstructionsLogic.usageNote(
                        hasInstructions: InstructionsLogic.effective(chat: nil, global: settings.systemPrompt) != nil,
                        defaultModelName: models.selected?.shortName))
                }
            }
            Section {
                ForEach(InstructionsLogic.templates) { template in
                    Button {
                        settings.systemPrompt = InstructionsLogic.inserting(template, into: settings.systemPrompt)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(template.title)
                            Text(template.text).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                    .foregroundStyle(.primary)
                    .accessibilityIdentifier("instructions.template.\(template.id)")
                }
            } header: {
                Text("Templates")
            } footer: {
                Text("Tap to add one. Presets keep their own prompt.")
            }
            Section {
                Button("Clear", role: .destructive) { settings.systemPrompt = "" }
                    .disabled(settings.systemPrompt.isEmpty)
            }
        }
        .navigationTitle("Custom Instructions")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Instructions for one chat, from its menu. They replace the global ones for this chat only.
struct ChatInstructionsSheet: View {
    let global: String
    var onSave: (String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String

    init(current: String?, global: String, onSave: @escaping (String?) -> Void) {
        self.global = global
        self.onSave = onSave
        _text = State(initialValue: current ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 160)
                        .accessibilityLabel("Instructions for this chat")
                        .accessibilityIdentifier("chat-instructions.editor")
                } footer: {
                    Text(footer)
                }
                if !text.isEmpty {
                    Section {
                        Button("Use my custom instructions", role: .destructive) { text = "" }
                    }
                }
            }
            .navigationTitle("This Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(role: .cancel) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) {
                        onSave(text)
                        dismiss()
                    }
                    .accessibilityIdentifier("chat-instructions.save")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var footer: String {
        InstructionsLogic.effective(chat: nil, global: global) == nil
            ? "Only this chat uses these instructions."
            : "Replaces your custom instructions in this chat only."
    }
}
