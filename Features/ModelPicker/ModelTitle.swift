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
                    // Shrinks a little first, so a long name stays readable at large text sizes, then cuts in the middle.
                    .minimumScaleFactor(0.8)
                    .truncationMode(.middle)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(.primary)
            // Room inside the system's glass capsule, which is as tall as the two side buttons.
            .padding(.horizontal, 12)
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
