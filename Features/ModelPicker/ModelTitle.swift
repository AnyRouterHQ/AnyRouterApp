import SwiftUI

/// The middle of the chat's top bar, a plain button between the two system glass buttons that opens the picker.
/// A chat with a reply shows its title on top and the model name under it in smaller type; otherwise the model name
/// alone, in bold. A long name truncates in the middle.
struct ModelTitle: View {
    var name: String?
    /// The chat's title (`ChatHeaderLogic.title`); nil shows only the model.
    var title: String? = nil
    var isLoading = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                if let title {
                    Text(title)
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .accessibilityIdentifier("chat.title")
                }
                Text(name ?? (isLoading ? "Loading…" : "Choose model"))
                    .font(title == nil ? .headline : .caption)
                    .foregroundStyle(title == nil ? .primary : .secondary)
                    .lineLimit(1)
                    // Shrinks a little first, so a long name stays readable at large text sizes, then cuts in the middle.
                    .minimumScaleFactor(0.8)
                    .truncationMode(.middle)
                    // The chevron hangs off the name's trailing edge without taking part in the layout, so the name is
                    // centred on the same axis as the title above it (operator: the subtitle looked indented).
                    .overlay(alignment: .trailing) {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .fixedSize()
                            .alignmentGuide(.trailing) { $0[.leading] - 4 }
                            .accessibilityHidden(true)
                    }
            }
            .foregroundStyle(.primary)
            // Room inside the system's glass capsule, which is as tall as the two side buttons.
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        // VoiceOver reads label then value: "Model, <name>"; the chat's title is in the hint.
        .accessibilityLabel("Model")
        .accessibilityValue(name ?? "")
        .accessibilityHint(title.map { "In \($0). Choose a model" } ?? "Choose a model")
        .accessibilityIdentifier("chat.model-title")
    }
}
