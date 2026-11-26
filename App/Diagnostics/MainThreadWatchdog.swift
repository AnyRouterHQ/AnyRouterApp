import Foundation
import UIKit
import os

/// Finds main-thread hangs: a timer on the main run loop leaves a heartbeat, a background thread checks it.
/// A stall is logged (subsystem `dev.anyrouter.app`, category `hang`) and kept for Settings > Diagnostics.
/// It reads nothing from the app's state, so it cannot cause a hang itself.
final class MainThreadWatchdog: @unchecked Sendable {
    static let shared = MainThreadWatchdog()

    static let threshold: TimeInterval = 0.25
    private static let interval: TimeInterval = 0.05
    private static let keep = 20

    private let lock = NSLock()
    private var lastBeat = ProcessInfo.processInfo.systemUptime
    private var context = "idle"
    private var stalls: [MainThreadStall] = []
    private var started = false
    /// While the app is in the background the system may suspend every thread, so a long gap is not a hang.
    private var inBackground = false
    private let log = Logger(subsystem: "dev.anyrouter.app", category: "hang")

    /// Newest first.
    var recent: [MainThreadStall] { lock.withLock { Array(stalls.reversed()) } }

    /// Names what is about to run on or wait for the main actor, so a stall report says where it happened.
    func mark(_ newContext: String) {
        lock.withLock { context = newContext }
    }

    /// Starts once. Call from the main thread.
    @MainActor func start() {
        let alreadyStarted = lock.withLock { () -> Bool in
            defer { started = true }
            return started
        }
        guard !alreadyStarted else { return }
        lock.withLock { inBackground = UIApplication.shared.applicationState == .background }
        let center = NotificationCenter.default
        center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: nil) { [weak self] _ in
            self?.setBackground(true)
        }
        center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: nil) { [weak self] _ in
            self?.setBackground(false)
        }
        let beat = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            self?.lock.withLock { self?.lastBeat = ProcessInfo.processInfo.systemUptime }
        }
        RunLoop.main.add(beat, forMode: .common)
        let thread = Thread { [weak self] in self?.watch() }
        thread.qualityOfService = .utility
        thread.name = "dev.anyrouter.watchdog"
        thread.start()
    }

    /// Entering the background stops the clock; coming back starts it from a fresh heartbeat, so the time the app
    /// was suspended is never reported as a stall.
    private func setBackground(_ on: Bool) {
        lock.withLock {
            inBackground = on
            if !on { lastBeat = ProcessInfo.processInfo.systemUptime }
        }
    }

    private func watch() {
        var tracker = StallTracker(threshold: Self.threshold)
        while true {
            Thread.sleep(forTimeInterval: Self.interval)
            let (beat, now, label, background) = lock.withLock {
                (lastBeat, ProcessInfo.processInfo.systemUptime, context, inBackground)
            }
            if background {
                tracker = StallTracker(threshold: Self.threshold)
                continue
            }
            if let duration = tracker.observe(now: now, lastBeat: beat) {
                let stall = MainThreadStall(date: Date(), duration: duration, context: label)
                lock.withLock {
                    stalls.append(stall)
                    if stalls.count > Self.keep { stalls.removeFirst(stalls.count - Self.keep) }
                }
                log.error("main thread stalled \(Int(duration * 1000)) ms during \(label, privacy: .public)")
            }
        }
    }
}
