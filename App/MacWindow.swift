import UIKit

/// The app on a Mac ("Designed for iPad"): windows get a minimum size, like any Mac app.
///
/// UIKit is allowed here (AGENTS.md): SwiftUI has no window size limit for an iOS app. Without a floor the window
/// can be dragged narrower than the split view needs, which flips the shell to the iPhone layout and rebuilds the chat.
/// On iPhone and iPad this does nothing.
@MainActor
enum MacWindow {
    static let minimumSize = CGSize(width: 820, height: 560)

    static func configure() {
        guard ProcessInfo.processInfo.isiOSAppOnMac else { return }
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            scene.sizeRestrictions?.minimumSize = minimumSize
        }
    }
}
