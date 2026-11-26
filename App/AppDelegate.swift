import UIKit

/// Receives the system's background URLSession wake-up so local model downloads can finish after relaunch.
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    private static var pendingCompletion: (() -> Void)?

    func application(_ application: UIApplication,
                     handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        Self.pendingCompletion = completionHandler
    }

    /// Called by the download manager once the session has delivered its events.
    static func finishBackgroundEvents() {
        pendingCompletion?()
        pendingCompletion = nil
    }
}
