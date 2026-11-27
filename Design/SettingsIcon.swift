import SwiftUI

/// The icon tile of a Settings row, drawn like the system Settings app: a white symbol on a rounded square of one
/// system color. A custom view because `Label` has no tile style; it scales with Dynamic Type.
struct SettingsIcon: View {
    let symbol: String
    let color: Color
    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 29

    var body: some View {
        Image(systemName: symbol)
            .font(.system(.footnote, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: side, height: side)
            .background(color, in: .rect(cornerRadius: side * 7 / 29))
            .accessibilityHidden(true)
    }
}

#Preview {
    VStack {
        SettingsIcon(symbol: "cube", color: .green)
        SettingsIcon(symbol: "cloud", color: .blue)
    }
}
