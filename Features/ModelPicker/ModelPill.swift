import SwiftUI

/// Center pill in the chat top bar showing the active model. Opens the picker.
struct ModelPill: View {
    var model: ModelDescriptor?
    var isLoading = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(model?.shortName ?? (isLoading ? "Loading…" : "Choose model"))
                    .font(.system(size: 15, weight: .medium))
                    .lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(ARColor.foreground)
            .padding(.horizontal, 14)
            .frame(height: ARTheme.controlSize)
            .arGlass(in: Capsule(), interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Model")
    }
}
