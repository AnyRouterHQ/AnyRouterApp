import Foundation
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
    private let log = Logger(subsystem: "dev.anyrouter.app", category: "hang")

    /// Newest first.
    var recent: [MainThreadStall] { lock.withLock { Array(stalls.reversed()) } }

    /// Names what is about to run on or wait for the main actor, so a stall report says where it happened.
    func mark(_ newContext: String) {
        lock.withLock { context = newContext }
    }

    /// Starts once. Call from the main thread.
    func start() {
        let alreadyStarted = lock.withLock { () -> Bool in
            defer { started = true }
            return started
        }
        guard !alreadyStarted else { return }
        let beat = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            self?.lock.withLock { self?.lastBeat = ProcessInfo.processInfo.systemUptime }
        }
        RunLoop.main.add(beat, forMode: .common)
        let thread = Thread { [weak self] in self?.watch() }
        thread.qualityOfService = .utility
        thread.name = "dev.anyrouter.watchdog"
        thread.start()
    }

    private func watch() {
        var tracker = StallTracker(threshold: Self.threshold)
        while true {
            Thread.sleep(forTimeInterval: Self.interval)
            let (beat, now, label) = lock.withLock { (lastBeat, ProcessInfo.processInfo.systemUptime, context) }
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
