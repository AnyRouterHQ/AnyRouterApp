import SwiftUI

/// The mark between the messages that were folded into a summary and the ones after them, as a trace row:
/// "Compacted conversation · 12 messages summarized". The messages above it stay readable; a tap opens the summary the
/// model works from.
struct CompactionDivider: View {
    let compaction: Compaction
    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { expanded.toggle() } label: {
                TraceRow(symbol: "rectangle.compress.vertical", isExpanded: expanded) {
                    Text("Compacted conversation · \(CompactionLogic.subtitle(droppedCount: compaction.droppedCount))")
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Compacted conversation")
            .accessibilityValue(CompactionLogic.subtitle(droppedCount: compaction.droppedCount))
            .accessibilityHint(expanded ? "Hides the summary" : "Shows the summary")
            .accessibilityIdentifier("compaction.divider")
            if expanded {
                Text(compaction.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, TraceRowMetrics.contentInset)
                    .padding(.bottom, 8)
                    .transition(.opacity)
                    .accessibilityIdentifier("compaction.summary")
            }
        }
        .animation(reduceMotion ? nil : .snappy, value: expanded)
    }
}
