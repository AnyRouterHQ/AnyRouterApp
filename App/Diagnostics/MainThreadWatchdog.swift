import Foundation
import UIKit
import os

/// Finds main-thread hangs without waking the device while the app is idle. A run loop observer on the main thread
/// notes when the main thread wakes up and when it goes back to sleep; a background thread sleeps until the main
/// thread wakes, then checks every 50 ms for as long as it stays busy. A stall is logged (subsystem
/// `dev.anyrouter.app`, category `hang`) and kept for Settings > Diagnostics. It reads nothing from the app's state,
/// so it cannot cause a hang itself. (An earlier version ran a 50 ms timer on the main thread and a 50 ms loop on a
/// second thread forever: 40 wake-ups a second while the app sat idle.)
final class MainThreadWatchdog: @unchecked Sendable {
    static let shared = MainThreadWatchdog()

    static let threshold: TimeInterval = 0.25
    private static let pollInterval: TimeInterval = 0.05
    private static let keep = 20

    private let lock = NSLock()
    /// The main thread is waiting for work (the run loop is asleep).
    private var mainIsIdle = false
    /// When the main thread last woke up. While it stays busy this is the start of the busy stretch.
    private var busySince = ProcessInfo.processInfo.systemUptime
    /// The watcher thread is asleep and wants a signal when the main thread wakes.
    private var parked = false
    private let wake = DispatchSemaphore(value: 0)
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
        lock.withLock {
            inBackground = UIApplication.shared.applicationState == .background
            busySince = ProcessInfo.processInfo.systemUptime
        }
        let center = NotificationCenter.default
        center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: nil) { [weak self] _ in
            self?.setBackground(true)
        }
        center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: nil) { [weak self] _ in
            self?.setBackground(false)
        }
        let activities: CFRunLoopActivity = [.afterWaiting, .beforeWaiting]
        let observer = CFRunLoopObserverCreateWithHandler(kCFAllocatorDefault, activities.rawValue, true, 0) { [weak self] _, activity in
            self?.runLoopChanged(activity)
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        let thread = Thread { [weak self] in self?.watch() }
        thread.qualityOfService = .utility
        thread.name = "dev.anyrouter.watchdog"
        thread.start()
    }

    /// Runs on the main thread, and only when it has something to do.
    private func runLoopChanged(_ activity: CFRunLoopActivity) {
        let now = ProcessInfo.processInfo.systemUptime
        let shouldWake = lock.withLock { () -> Bool in
            if activity.contains(.afterWaiting) {
                mainIsIdle = false
                busySince = now
                defer { parked = false }
                return parked
            }
            mainIsIdle = true
            return false
        }
        if shouldWake { wake.signal() }
    }

    /// Entering the background stops the clock; coming back starts it from a fresh heartbeat, so the time the app
    /// was suspended is never reported as a stall.
    private func setBackground(_ on: Bool) {
        lock.withLock {
            inBackground = on
            if !on { busySince = ProcessInfo.processInfo.systemUptime }
        }
    }

    private func watch() {
        var tracker = StallTracker(threshold: Self.threshold)
        while true {
            // Asleep until the main thread wakes: an idle app costs nothing here. If it woke in the meantime, look now.
            let mainIsBusy = lock.withLock { () -> Bool in
                if !mainIsIdle { return true }
                parked = true
                return false
            }
            if !mainIsBusy { wake.wait() }
            // The main thread is working. Check on it until it sleeps again and no stall is open.
            while true {
                Thread.sleep(forTimeInterval: Self.pollInterval)
                let (idle, since, now, label, background) = lock.withLock {
                    (mainIsIdle, busySince, ProcessInfo.processInfo.systemUptime, context, inBackground)
                }
                if background {
                    tracker = StallTracker(threshold: Self.threshold)
                    break
                }
                let beat = StallTracker.lastBeat(mainIsIdle: idle, busySince: since, now: now)
                if let duration = tracker.observe(now: now, lastBeat: beat) {
                    let stall = MainThreadStall(date: Date(), duration: duration, context: label)
                    lock.withLock {
                        stalls.append(stall)
                        if stalls.count > Self.keep { stalls.removeFirst(stalls.count - Self.keep) }
                    }
                    log.error("main thread stalled \(Int(duration * 1000)) ms during \(label, privacy: .public)")
                }
                if idle && !tracker.isStalled { break }
            }
        }
    }
}
