import SwiftUI

/// The reasoning of a reply as one quiet row: a clock, "Thinking…" with a shimmer while it writes and "Thought for 12s"
/// after, and a chevron. Tap it for the full text in secondary style. While it writes, the collapsed row also shows the
/// line written last.
struct ReasoningRow: View {
    let trace: ReasoningTrace
    let isStreaming: Bool
    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { expanded.toggle() } label: {
                PartRowLabel(symbol: "clock", isExpanded: expanded) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(ReasoningLogic.title(durationMs: trace.durationMs, isStreaming: isStreaming))
                            .shimmering(isStreaming)
                        if isStreaming, !expanded, let line = ReasoningLogic.latestLine(trace.text) {
                            Text(line).font(.caption).lineLimit(1)
                        }
                    }
                } trailing: {
                    EmptyView()
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint(expanded ? "Hides the reasoning" : "Shows the reasoning")
            .accessibilityIdentifier("reasoning.row")
            if expanded {
                Text(trace.text)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, PartRowMetrics.contentInset)
                    .padding(.bottom, 8)
                    .transition(.opacity)
                    .accessibilityIdentifier("reasoning.text")
            }
        }
        .animation(reduceMotion ? nil : .snappy, value: expanded)
    }
}

/// A band of light that sweeps over the text while `active`. Still under Reduce Motion.
/// Driven by a timeline, not a repeating animation: the frames stop as soon as the reasoning ends or the row
/// leaves the screen, where a `repeatForever` animation can keep running on a state nothing shows.
private struct Shimmer: ViewModifier {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if active && !reduceMotion {
            TimelineView(.animation) { timeline in
                // One sweep every 1.6 s, from half a width before the text to its trailing edge.
                let phase = -0.5 + 1.5 * timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
                content
                    .overlay {
                        content
                            .foregroundStyle(.primary)
                            .mask {
                                GeometryReader { proxy in
                                    LinearGradient(colors: [.clear, .black, .clear], startPoint: .leading, endPoint: .trailing)
                                        .frame(width: proxy.size.width * 0.6)
                                        .offset(x: proxy.size.width * phase)
                                }
                            }
                    }
            }
        } else {
            content
        }
    }
}

extension View {
    func shimmering(_ active: Bool) -> some View { modifier(Shimmer(active: active)) }
}
