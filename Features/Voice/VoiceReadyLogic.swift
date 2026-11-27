import Foundation

/// How the person hears that Voice Mode is ready. No views and no system calls here.
enum VoiceReadyLogic {
    enum Permission: Equatable, Sendable {
        case notDetermined
        case granted
        case denied
    }

    enum Announcement: Equatable, Sendable {
        /// The app is in front: the banner and a haptic.
        case banner
        /// The app is away and may send notifications: one local notification.
        case notification
        /// The app is away and may not notify: the banner waits for the next visit.
        case nothing
    }

    static let title = "Voice Mode is ready"

    static func announcement(appIsActive: Bool, permission: Permission) -> Announcement {
        if appIsActive { return .banner }
        return permission == .granted ? .notification : .nothing
    }

    /// Ask when the person taps Download (the app is in front then), and only once: never when they already answered.
    static func shouldAsk(_ permission: Permission) -> Bool { permission == .notDetermined }

    static func notificationBody(modelTitle: String?) -> String {
        guard let modelTitle else { return "Tap to start." }
        return "\(modelTitle) is on your phone. Tap to start."
    }
}
