import SwiftUI

/// Center pill in the chat top bar showing the active model. Opens the picker.
struct ModelPill: View {
    var model: ModelDescriptor?
    var isLoading = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let model {
                    ModelLabel(model: model, style: .pill)
                } else {
                    Text(isLoading ? "Loading…" : "Choose model").font(.subheadline.weight(.medium)).lineLimit(1)
                }
                Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
            }
            .foregroundStyle(.primary)
        }
        .buttonStyle(.glass)
        .controlSize(.large)
        .accessibilityLabel("Model")
        .accessibilityValue(model?.shortName ?? "")
    }
}
