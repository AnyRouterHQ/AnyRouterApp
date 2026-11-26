import SwiftUI

/// The chat title: the active model's name in bold with a small chevron. A plain button, no capsule, between the two
/// system glass buttons of the top bar. Opens the picker. A long name truncates in the middle.
struct ModelTitle: View {
    var name: String?
    var isLoading = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(name ?? (isLoading ? "Loading…" : "Choose model"))
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(.primary)
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        // VoiceOver reads label then value: "Model, <name>".
        .accessibilityLabel("Model")
        .accessibilityValue(name ?? "")
        .accessibilityHint("Choose a model")
        .accessibilityIdentifier("chat.model-title")
    }
}
