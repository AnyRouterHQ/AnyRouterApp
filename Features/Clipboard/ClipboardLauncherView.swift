import SwiftUI

/// Above the composer when text was copied elsewhere: the system's Paste button first (it needs no permission alert),
/// then the presets that work on text. Tapping a preset reads the clipboard and sends; that read is the person's own tap.
struct ClipboardLauncherRow: View {
    let presets: [PromptPreset]
    var onPaste: (String) -> Void
    var onPreset: (PromptPreset) -> Void
    var onDismiss: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                PasteButton(payloadType: String.self) { onPaste($0.joined(separator: "\n")) }
                    .buttonBorderShape(.capsule)
                ForEach(presets) { preset in
                    Button { onPreset(preset) } label: {
                        Label(preset.title, systemImage: preset.symbol).frame(minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                }
                Button(role: .close, action: onDismiss)
                    .accessibilityLabel("Hide clipboard actions")
            }
        }
        .accessibilityIdentifier("composer.clipboard")
    }
}
