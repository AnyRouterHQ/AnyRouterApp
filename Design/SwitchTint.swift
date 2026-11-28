import SwiftUI

/// Switches stay system green, like iOS Settings. The app tint is mono (white in dark mode), which made an ON switch a
/// white knob on a white track (HIG audit 2026-11-28 #1).
struct GreenSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Toggle(configuration).toggleStyle(.switch).tint(.green)
    }
}

extension View {
    /// Green switches for a form, a list or a sheet that draws them. Never set it above a Menu that holds a Toggle:
    /// it forces a switch, which a menu cannot draw, so the menu showed blank rows (lane B, 29ac88c). That is why it is
    /// not set once at the app's root.
    func formSwitches() -> some View {
        toggleStyle(GreenSwitchStyle())
    }
}
