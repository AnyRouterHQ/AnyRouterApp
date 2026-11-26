import Foundation
import os

/// One time the main thread did not answer for longer than the threshold.
struct MainThreadStall: Equatable, Sendable {
    var date: Date
    var duration: TimeInterval
    /// What the app said it was doing (see `MainThreadWatchdog.mark`). Fixed words only, never user text.
    var context: String
}

/// The bookkeeping, with no threads: feed it the time and the time of the last main-thread heartbeat.
struct StallTracker: Equatable {
    var threshold: TimeInterval
    private var stalledSince: TimeInterval?

    init(threshold: TimeInterval) {
        self.threshold = threshold
    }

    var isStalled: Bool { stalledSince != nil }

    /// Returns the length of a stall once the main thread has answered again, nil otherwise.
    mutating func observe(now: TimeInterval, lastBeat: TimeInterval) -> TimeInterval? {
        if let since = stalledSince {
            guard lastBeat > since else { return nil }
            stalledSince = nil
            return lastBeat - since
        }
        if now - lastBeat >= threshold { stalledSince = lastBeat }
        return nil
    }
}
