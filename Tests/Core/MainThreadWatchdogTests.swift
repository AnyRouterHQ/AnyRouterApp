import Foundation
import Testing
@testable import AnyRouter

struct StallTrackerTests {
    @Test func aHeartbeatWithinTheThresholdIsNotAStall() {
        var tracker = StallTracker(threshold: 0.25)
        #expect(tracker.observe(now: 10.0, lastBeat: 9.95) == nil)
        #expect(tracker.observe(now: 10.2, lastBeat: 10.0) == nil)
        #expect(!tracker.isStalled)
    }

    @Test func aStallIsReportedWhenTheMainThreadAnswersAgainWithItsFullLength() {
        var tracker = StallTracker(threshold: 0.25)
        #expect(tracker.observe(now: 10.3, lastBeat: 10.0) == nil, "still unresponsive: nothing to report yet")
        #expect(tracker.isStalled)
        #expect(tracker.observe(now: 12.0, lastBeat: 10.0) == nil)
        let length = tracker.observe(now: 12.05, lastBeat: 12.04)
        #expect(length != nil && abs((length ?? 0) - 2.04) < 0.0001)
        #expect(!tracker.isStalled)
    }

    @Test func eachStallIsReportedOnce() {
        var tracker = StallTracker(threshold: 0.25)
        _ = tracker.observe(now: 5.0, lastBeat: 4.0)
        #expect(tracker.observe(now: 5.1, lastBeat: 5.1) != nil)
        #expect(tracker.observe(now: 5.2, lastBeat: 5.15) == nil)
    }

    /// The watchdog parks while the main thread sleeps, so an idle app has no timers: this is what it reads instead.
    @Test func aSleepingMainThreadIsAlwaysResponsiveAndABusyOneSinceItWoke() {
        #expect(StallTracker.lastBeat(mainIsIdle: true, busySince: 3.0, now: 9.0) == 9.0)
        #expect(StallTracker.lastBeat(mainIsIdle: false, busySince: 3.0, now: 9.0) == 3.0)
        var tracker = StallTracker(threshold: 0.25)
        // Busy since 3.0, looked at 3.3 s later: a stall opens.
        #expect(tracker.observe(now: 3.3, lastBeat: StallTracker.lastBeat(mainIsIdle: false, busySince: 3.0, now: 3.3)) == nil)
        #expect(tracker.isStalled)
        // The main thread goes to sleep at 3.6: the stall closes with its length.
        let length = tracker.observe(now: 3.6, lastBeat: StallTracker.lastBeat(mainIsIdle: true, busySince: 3.0, now: 3.6))
        #expect(length != nil && abs((length ?? 0) - 0.6) < 0.0001)
    }
}
