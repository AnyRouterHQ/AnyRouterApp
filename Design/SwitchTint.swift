import SwiftUI

/// Switches stay system green, like iOS Settings. The app tint is mono (white in dark mode), which made an ON switch a
/// white knob on a white track (HIG audit 2026-11-28 #1). Set once at the root; buttons and links keep the mono tint.
extension View {
    /// The app's one tint and green switches. Set at the root and again on each sheet: a sheet the shell presents did not
    /// get the switch style from the root (Settings › Memory switches were mono in screenshots 46075429647).
    func appControls() -> some View {
        tint(ARPalette.tint).toggleStyle(GreenSwitchStyle())
    }
}

struct GreenSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Toggle(configuration).toggleStyle(.switch).tint(.green)
    }
}
