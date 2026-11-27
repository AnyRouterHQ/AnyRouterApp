import Foundation
import UserNotifications

/// The local notification "Voice Mode is ready", behind a seam so tests do not touch the notification center.
@MainActor
protocol ReadyNotifying: AnyObject {
    func permission() async -> VoiceReadyLogic.Permission
    func requestPermission() async
    func post(title: String, body: String) async
}

/// Says no to everything. For tests and previews; the app passes `SystemReadyNotifier`.
@MainActor
final class InertReadyNotifier: ReadyNotifying {
    func permission() async -> VoiceReadyLogic.Permission { .denied }
    func requestPermission() async {}
    func post(title: String, body: String) async {}
}

@MainActor
final class SystemReadyNotifier: ReadyNotifying {
    private let center = UNUserNotificationCenter.current()

    func permission() async -> VoiceReadyLogic.Permission {
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: .granted
        case .denied: .denied
        case .notDetermined: .notDetermined
        @unknown default: .denied
        }
    }

    /// The system asks once; a later call answers without a prompt. A refusal is a normal answer, so nothing is thrown.
    func requestPermission() async {
        _ = try? await center.requestAuthorization(options: [.alert])
    }

    /// Best effort: a notification that cannot be scheduled costs the person only a missed ping, the banner is still there.
    func post(title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        try? await center.add(UNNotificationRequest(identifier: "voice-mode-ready", content: content, trigger: nil))
    }
}
