import SwiftUI

/// The presets offered after a paste, as one row of stock buttons above the field. Tap applies the preset to the
/// pasted text; the close button hides the row.
struct PasteOfferRow: View {
    let presets: [PromptPreset]
    var onPick: (PromptPreset) -> Void
    var onDismiss: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(presets) { preset in
                    Button { onPick(preset) } label: {
                        Label(preset.title, systemImage: preset.symbol).frame(minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                }
                Button(role: .close, action: onDismiss)
                    .accessibilityLabel("Hide presets")
            }
        }
        .accessibilityIdentifier("composer.paste-offer")
    }
}
