import Foundation
import Observation
import UIKit

struct SystemPasteboard: PasteboardProbe {
    var changeCount: Int { UIPasteboard.general.changeCount }
    var hasStrings: Bool { UIPasteboard.general.hasStrings }
}

/// A pasteboard that is always empty, for demo runs and screenshots.
struct EmptyPasteboard: PasteboardProbe {
    var changeCount: Int { 0 }
    var hasStrings: Bool { false }
}

/// Decides when the chat shows its clipboard row. It only ever reads `changeCount` and `hasStrings`: reading the text
/// itself shows the system's "Allow Paste" alert every time, so the text is read by the system's Paste button, or by
/// the person tapping a preset.
@MainActor @Observable
final class ClipboardLauncher {
    private static let seenKey = "clipboard.lastOfferedChangeCount"

    private(set) var isOffered = false
    @ObservationIgnored private let probe: any PasteboardProbe
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var watcher: (any NSObjectProtocol)?

    init(probe: any PasteboardProbe = SystemPasteboard(), defaults: UserDefaults = .standard) {
        self.probe = probe
        self.defaults = defaults
    }

    /// Call when the app becomes active and the composer shows. The same clipboard is offered once.
    func check(composerEmpty: Bool) {
        let count = probe.changeCount
        let seen = defaults.object(forKey: Self.seenKey) as? Int
        guard ClipboardLaunchLogic.shouldOffer(
            changeCount: count, lastSeen: seen, hasStrings: probe.hasStrings, composerEmpty: composerEmpty) else { return }
        defaults.set(count, forKey: Self.seenKey)
        isOffered = true
    }

    func dismiss() { isOffered = false }

    /// The app itself copied something (a reply's Copy button): that text is not offered back.
    func noteOwnCopy() {
        defaults.set(probe.changeCount, forKey: Self.seenKey)
        isOffered = false
    }

    /// Treats a pasteboard change while the app is in front as its own.
    func startWatching() {
        guard watcher == nil else { return }
        watcher = NotificationCenter.default.addObserver(
            forName: UIPasteboard.changedNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                if UIApplication.shared.applicationState == .active { self?.noteOwnCopy() }
            }
        }
    }
}
