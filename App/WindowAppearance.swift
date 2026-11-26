import UIKit

/// Applies the theme setting to every window.
///
/// This is the documented case where UIKit is allowed (AGENTS.md): SwiftUI's `preferredColorScheme`
/// is not re-read by sheets that are already presented and does not revert to System from an explicit
/// Light or Dark. Setting `overrideUserInterfaceStyle` on the window changes the traits of the whole
/// hierarchy at once (open sheets, the drawer, dynamic color tokens, `@Environment(\.colorScheme)`).
@MainActor
enum WindowAppearance {
    static func apply(_ appearance: AppSettings.Appearance) {
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows {
                window.overrideUserInterfaceStyle = appearance.userInterfaceStyle
            }
        }
    }
}
