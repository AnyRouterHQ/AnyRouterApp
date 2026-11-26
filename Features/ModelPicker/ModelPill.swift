import SwiftUI

/// Center pill in the chat top bar showing the active model. Opens the picker.
struct ModelPill: View {
    @Environment(ModelStore.self) private var models
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(models.selected?.displayName ?? (models.isLoading ? "Loading…" : "Choose model"))
                    .font(.system(size: 15, weight: .medium))
                    .lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(ARColor.foreground)
            .padding(.horizontal, 14)
            .frame(height: ARTheme.controlSize)
            .background(ARColor.card, in: Capsule())
            .overlay(Capsule().strokeBorder(ARColor.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Model")
    }
}
