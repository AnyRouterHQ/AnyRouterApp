import SwiftUI

/// The @ list above the composer: a glass panel with one row per plugin or file, the kind in grey at the end.
/// Choosing a row keeps the keyboard up, because the panel sits inside the composer.
struct MentionSuggestions: View {
    let items: [MentionItem]
    /// Set when the list was opened from the + menu: it has no @ to end it, so it gets a close button.
    var onClose: (() -> Void)?
    let onPick: (MentionItem) -> Void

    @ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = 44
    private let visibleRows = 5

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(ComposerMention.prompt).font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                if let onClose {
                    Button(role: .close, action: onClose)
                        .accessibilityIdentifier("mention.close")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 4)
            if items.isEmpty {
                Text("No plugin or file matches.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: rowHeight, alignment: .leading)
                    .padding(.horizontal, 16)
            } else {
                List(items) { item in
                    Button { onPick(item) } label: {
                        HStack {
                            Label { Text(item.title) } icon: { ToolSourceIcon(icon: item.icon) }
                            Spacer()
                            // The reason or the switch is words, not only a dimmed row.
                            Text(item.detail).font(.subheadline).foregroundStyle(.secondary)
                        }
                        .frame(minHeight: rowHeight)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .disabled(!item.isAvailable)
                    .accessibilityIdentifier("mention.\(item.id)")
                    .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.defaultMinListRowHeight, rowHeight)
                .frame(height: rowHeight * CGFloat(min(items.count, visibleRows)))
            }
        }
        // A floating panel over the chat, so it takes glass directly, like the composer field.
        .glassEffect(.regular, in: .rect(cornerRadius: ARTheme.radiusXL))
        .accessibilityIdentifier("mention.panel")
    }
}

/// The plugins and files already chosen for the next message, each removable.
struct MentionChips: View {
    let mentions: [MentionItem]
    let onRemove: (MentionItem) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(mentions) { item in
                    Button { onRemove(item) } label: {
                        HStack(spacing: 6) {
                            Label { Text(item.title) } icon: { ToolSourceIcon(icon: item.icon) }
                            Image(systemName: "xmark").font(.caption)
                        }
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .frame(minHeight: 44)
                    .accessibilityLabel("Remove \(item.title)")
                    .accessibilityIdentifier("mention.chip.\(item.id)")
                }
            }
        }
    }
}
