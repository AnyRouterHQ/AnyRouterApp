import SwiftUI

/// The one row of a reply's trace (decision D27): reasoning, the tool chain and each call, subagents, compaction.
/// An icon, one or two lines of words, the status, a chevron. The rows share the metrics below, so their texts line up;
/// expanded content starts under the text: `TraceRowMetrics.contentInset`.
struct TraceRow<Icon: View, Title: View>: View {
    let status: TraceStatus?
    let isExpanded: Bool
    let icon: Icon
    let title: Title

    init(status: TraceStatus? = nil, isExpanded: Bool, @ViewBuilder icon: () -> Icon, @ViewBuilder title: () -> Title) {
        self.status = status
        self.isExpanded = isExpanded
        self.icon = icon()
        self.title = title()
    }

    var body: some View {
        HStack(spacing: TraceRowMetrics.spacing) {
            icon.frame(width: TraceRowMetrics.symbolWidth)
            title
            Spacer(minLength: 8)
            if let status { TraceStatusGlyph(status: status) }
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

extension TraceRow where Icon == Image {
    init(symbol: String, status: TraceStatus? = nil, isExpanded: Bool, @ViewBuilder title: () -> Title) {
        self.init(status: status, isExpanded: isExpanded, icon: { Image(systemName: symbol) }, title: title)
    }
}

/// The trailing mark of a status. Done shows a check; a folded summary passes no status instead.
struct TraceStatusGlyph: View {
    let status: TraceStatus

    var body: some View {
        Group {
            switch status {
            case .running: ProgressView().controlSize(.small)
            case .awaitingApproval: Image(systemName: "clock.badge.questionmark").foregroundStyle(.orange)
            case .done: Image(systemName: "checkmark.circle")
            case .failed: Image(systemName: "exclamationmark.triangle").foregroundStyle(.red)
            case .denied: Image(systemName: "hand.raised")
            case .cancelled: Image(systemName: "xmark.circle")
            }
        }
        .accessibilityLabel(status.accessibilityText)
    }
}

enum TraceRowMetrics {
    static let symbolWidth: CGFloat = 22
    static let spacing: CGFloat = 8
    /// Where the expanded content starts: under the row's text.
    static let contentInset: CGFloat = symbolWidth + spacing
}
