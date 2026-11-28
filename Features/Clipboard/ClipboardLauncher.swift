import Foundation
import Observation
import UIKit

struct SystemPasteboard: PasteboardProbe {
    var changeCount: Int { UIPasteboard.general.changeCount }
    var hasStrings: Bool { UIPasteboard.general.hasStrings }
    var hasURLs: Bool { UIPasteboard.general.hasURLs }
    var hasImages: Bool { UIPasteboard.general.hasImages }

    /// Pattern detection does not show the paste alert: it says a link is likely, never what the text is.
    func hasProbableWebURL() async -> Bool {
        await withCheckedContinuation { continuation in
            UIPasteboard.general.detectPatterns(for: [.probableWebURL]) { result in
                continuation.resume(returning: (try? result.get())?.contains(.probableWebURL) == true)
            }
        }
    }
}

/// A pasteboard that is always empty, for demo runs and screenshots.
struct EmptyPasteboard: PasteboardProbe {
    var changeCount: Int { 0 }
    var hasStrings: Bool { false }
}

/// A pasteboard that always has text and a count that differs on every launch, so a demo run offers the clipboard row.
/// The text itself is not here: the screenshot test puts it on the system pasteboard for the Paste button to read.
struct DemoPasteboard: PasteboardProbe {
    var changeCount: Int { Int(ProcessInfo.processInfo.systemUptime) }
    var hasStrings: Bool { true }
}

/// Decides when the chat shows its clipboard row. It only ever reads `changeCount` and the `has…` flags: reading the text
/// itself shows the system's "Allow Paste" alert every time, so the text is read by the system's Paste button, or by
/// the person tapping a preset.
@MainActor @Observable
final class ClipboardLauncher {
    private static let seenKey = "clipboard.lastOfferedChangeCount"
    private static let ownCopyKey = "clipboard.ownCopyChangeCount"

    /// What the offered copy is, or nil when nothing is offered.
    private(set) var offeredKind: ClipboardKind?
    /// What is on the clipboard now, or nil when it is empty or the app's own copy. Unlike the offer it stays for every
    /// new chat until the next copy.
    private(set) var contentKind: ClipboardKind?
    var isOffered: Bool { offeredKind != nil }
    @ObservationIgnored private let probe: any PasteboardProbe
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var watcher: (any NSObjectProtocol)?

    init(probe: any PasteboardProbe = SystemPasteboard(), defaults: UserDefaults = .standard) {
        self.probe = probe
        self.defaults = defaults
    }

    /// Call when the app becomes active and the composer shows. The same clipboard is offered once. Plain text that is
    /// probably a link turns into a link when the returned task ends.
    @discardableResult
    func check(composerEmpty: Bool) -> Task<Void, Never>? {
        let count = probe.changeCount
        let kind = ClipboardLaunchLogic.kind(hasStrings: probe.hasStrings, hasURLs: probe.hasURLs, hasImages: probe.hasImages)
        contentKind = count == (defaults.object(forKey: Self.ownCopyKey) as? Int) ? nil : kind
        if let kind, ClipboardLaunchLogic.shouldOffer(
            changeCount: count, lastSeen: defaults.object(forKey: Self.seenKey) as? Int, hasStrings: true,
            composerEmpty: composerEmpty) {
            defaults.set(count, forKey: Self.seenKey)
            offeredKind = kind
        }
        guard kind == .text else { return nil }
        return Task { [probe] in
            guard await probe.hasProbableWebURL(), probe.changeCount == count else { return }
            if contentKind == .text { contentKind = .link }
            if offeredKind == .text { offeredKind = .link }
        }
    }

    /// The offer was used or typed over: its chip goes. The cards stay for the next new chat.
    func dismiss() { offeredKind = nil }

    /// The app itself copied something (a reply's Copy button): that text is not offered back, and the cards do not
    /// act on it, until the next copy.
    func noteOwnCopy() {
        defaults.set(probe.changeCount, forKey: Self.seenKey)
        defaults.set(probe.changeCount, forKey: Self.ownCopyKey)
        offeredKind = nil
        contentKind = nil
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
