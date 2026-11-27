import SwiftUI

/// Switches stay system green, like iOS Settings. The app tint is mono (white in dark mode), which made an ON switch a
/// white knob on a white track (HIG audit 2026-11-28 #1). Set once at the root; buttons and links keep the mono tint.
struct GreenSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Toggle(configuration).toggleStyle(.switch).tint(.green)
    }
}
