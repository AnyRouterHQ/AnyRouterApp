import SwiftUI

/// The mark between the messages that were folded into a summary and the ones after them: a wavy line on both sides of
/// "Compacted conversation". The messages above it stay readable; a tap opens the summary the model works from.
struct CompactionDivider: View {
    let compaction: Compaction
    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 8) {
            Button { expanded.toggle() } label: {
                HStack(spacing: 12) {
                    WaveLine().stroke(.tertiary, lineWidth: 1).frame(height: 6)
                    Text("Compacted conversation").font(.footnote).foregroundStyle(.secondary).fixedSize()
                    WaveLine().stroke(.tertiary, lineWidth: 1).frame(height: 6)
                }
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Compacted conversation")
            .accessibilityValue(CompactionLogic.subtitle(droppedCount: compaction.droppedCount))
            .accessibilityHint(expanded ? "Hides the summary" : "Shows the summary")
            .accessibilityIdentifier("compaction.divider")
            if expanded {
                VStack(alignment: .leading, spacing: 6) {
                    Text(CompactionLogic.subtitle(droppedCount: compaction.droppedCount))
                        .font(.caption.weight(.semibold))
                    Text(compaction.summary).font(.callout).textSelection(.enabled)
                }
                .foregroundStyle(.secondary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 14))
                .transition(.opacity)
                .accessibilityIdentifier("compaction.summary")
            }
        }
        .animation(reduceMotion ? nil : .snappy, value: expanded)
    }
}

/// A hairline that runs as a sine wave across its width.
struct WaveLine: Shape {
    static let wavelength: CGFloat = 8

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let amplitude = rect.height / 2
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        var x = rect.minX
        while x <= rect.maxX {
            let phase = (x - rect.minX) / Self.wavelength * 2 * .pi
            path.addLine(to: CGPoint(x: x, y: rect.midY + amplitude * sin(phase)))
            x += 1
        }
        return path
    }
}
