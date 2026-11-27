import SwiftUI

/// The one row that heads a collapsible part of a reply (reasoning, tool steps, a subagent): a symbol in a fixed-width
/// slot, one line of words, anything that says how it is going, and a chevron. All three look the same, in secondary grey,
/// so their texts line up. The expanded content starts under the text: `PartRowMetrics.contentInset`.
struct PartRowLabel<Title: View, Trailing: View>: View {
    let symbol: String
    let isExpanded: Bool
    @ViewBuilder var title: Title
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: PartRowMetrics.spacing) {
            Image(systemName: symbol).frame(width: PartRowMetrics.symbolWidth)
            title
            Spacer(minLength: 8)
            trailing
            Image(systemName: "chevron.right")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(minHeight: 44)
        .contentShape(.rect)
    }
}

enum PartRowMetrics {
    static let symbolWidth: CGFloat = 22
    static let spacing: CGFloat = 8
    /// Where the expanded content starts: under the row's text.
    static let contentInset: CGFloat = symbolWidth + spacing
}
