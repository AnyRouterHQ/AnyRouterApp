import SwiftUI

extension Color {
    /// The label color on a prominent button: the inverse of the accent, so white on black in light mode and black on
    /// white in dark mode. The system draws the label of `.borderedProminent` and `.glassProminent` in a fixed light
    /// color, which disappears on the mono accent (white in dark mode).
    static let accentForeground = Color("AccentForeground")
}

extension View {
    /// Put this on the label inside a `.borderedProminent` or `.glassProminent` button.
    func prominentLabel() -> some View {
        foregroundStyle(Color.accentForeground)
    }
}
