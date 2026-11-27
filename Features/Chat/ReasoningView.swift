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
                HStack(spacing: 8) {
                    Image(systemName: "clock")
                    VStack(alignment: .leading, spacing: 0) {
                        Text(ReasoningLogic.title(durationMs: trace.durationMs, isStreaming: isStreaming))
                            .font(.footnote)
                            .shimmering(isStreaming)
                        if isStreaming, !expanded, let line = ReasoningLogic.latestLine(trace.text) {
                            Text(line).font(.caption).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .imageScale(.small)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .foregroundStyle(.secondary)
                .frame(minHeight: 44)
                .contentShape(.rect)
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
                    .padding(.bottom, 8)
                    .transition(.opacity)
                    .accessibilityIdentifier("reasoning.text")
            }
        }
        .animation(reduceMotion ? nil : .snappy, value: expanded)
    }
}

/// A band of light that sweeps over the text while `active`. Still under Reduce Motion.
private struct Shimmer: ViewModifier {
    let active: Bool
    @State private var phase: CGFloat = -0.5
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if active && !reduceMotion {
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
                .onAppear {
                    withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) { phase = 1 }
                }
        } else {
            content
        }
    }
}

extension View {
    func shimmering(_ active: Bool) -> some View { modifier(Shimmer(active: active)) }
}
