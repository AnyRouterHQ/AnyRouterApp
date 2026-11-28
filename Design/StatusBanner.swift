import SwiftUI

/// A status line above the composer: tinted glass, a red symbol, primary text and a plain close glyph (no glass inside
/// glass). It sits in the composer's glass container; lane A uses it for errors too.
struct StatusBanner: View {
    let text: String
    var onDismiss: () -> Void
    @ScaledMetric(relativeTo: .callout) private var closeSide: CGFloat = 44

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Label {
                Text(text).foregroundStyle(.primary)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
            }
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
            Button(action: onDismiss) {
                Label("Close", systemImage: "xmark")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
                    .frame(width: closeSide, height: closeSide)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 12)
        .glassEffect(.regular.tint(.red.opacity(0.15)), in: .rect(cornerRadius: ARTheme.radiusLarge))
    }
}
