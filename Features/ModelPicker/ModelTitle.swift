import SwiftUI

/// The middle of the chat's top bar, a plain button between the two system glass buttons that opens the picker.
/// A chat with a reply shows its title on top and the model name under it in smaller type; otherwise the model name
/// alone, in bold. A long name truncates in the middle.
struct ModelTitle: View {
    var name: String?
    /// The chat's title (`ChatHeaderLogic.title`); nil shows only the model.
    var title: String? = nil
    /// "Instructions" when this chat has its own instructions (`InstructionsLogic.headerTag`), inside the pill.
    var tag: String? = nil
    var isLoading = false
    /// The model's logo before its name. The mini apps show it; the chat header does not.
    var brand: ModelBrand? = nil
    var identifier = "chat.model-title"
    var action: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            pill
            // Outside the button, so VoiceOver and the UI tests read it as its own text.
            if let tag {
                Text(tag).font(.caption2).foregroundStyle(.secondary).accessibilityIdentifier("chat.instructions-tag")
            }
        }
    }

    private var pill: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                if let title {
                    Text(title)
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .accessibilityIdentifier("chat.title")
                }
                HStack(spacing: 6) {
                    if let brand { PillLogo(brand: brand) }
                    nameText
                }
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        // Plain text, no shape (operator): the chat list's hard top edge keeps reply text from reading through it.
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        // VoiceOver reads label then value: "Model, <name>"; the chat's title is in the hint.
        .accessibilityLabel("Model")
        .accessibilityValue(AccessibilityLogic.modelPillValue(name: name, isLoading: isLoading))
        .accessibilityHint(title.map { "In \($0). Choose a model" } ?? "Choose a model")
        .accessibilityIdentifier(identifier)
    }

    private var nameText: some View {
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
}

/// The logo at the size of the headline next to it.
private struct PillLogo: View {
    let brand: ModelBrand
    @ScaledMetric(relativeTo: .headline) private var size: CGFloat = 20

    var body: some View { ModelLogo(brand: brand, size: size) }
}
