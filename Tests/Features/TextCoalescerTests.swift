import Foundation
import Testing
@testable import AnyRouter

struct TextCoalescerTests {
    @Test func theFirstPieceShowsAtOnce() {
        var coalescer = TextCoalescer(interval: 0.05)
        #expect(coalescer.add("Hel", now: 1.0) == "Hel")
    }

    @Test func piecesInsideTheIntervalAreHeldAndJoinedInOrder() {
        var coalescer = TextCoalescer(interval: 0.05)
        _ = coalescer.add("a", now: 1.00)
        #expect(coalescer.add("b", now: 1.01) == nil)
        #expect(coalescer.add("c", now: 1.02) == nil)
        #expect(coalescer.add("d", now: 1.06) == "bcd")
    }

    @Test func aSlowModelShowsEveryTokenAtOnce() {
        var coalescer = TextCoalescer(interval: 0.05)
        #expect(coalescer.add("a", now: 1.0) == "a")
        #expect(coalescer.add("b", now: 1.2) == "b")
        #expect(coalescer.add("c", now: 1.4) == "c")
    }

    @Test func flushReturnsWhatIsHeldOnceAndNothingAfter() {
        var coalescer = TextCoalescer(interval: 0.05)
        _ = coalescer.add("a", now: 1.0)
        _ = coalescer.add("b", now: 1.01)
        #expect(coalescer.flush() == "b")
        #expect(coalescer.flush() == nil)
    }

    @Test func nothingIsLostOrReorderedOverALongBurst() {
        var coalescer = TextCoalescer(interval: 0.05)
        var shown = ""
        for index in 0..<500 {
            if let text = coalescer.add("\(index) ", now: 1.0 + Double(index) * 0.004) { shown += text }
        }
        if let rest = coalescer.flush() { shown += rest }
        #expect(shown == (0..<500).map { "\($0) " }.joined())
    }

    @Test func aBurstOfFiveHundredTokensCausesFarFewerUpdates() {
        var coalescer = TextCoalescer(interval: 0.05)
        var updates = 0
        for index in 0..<500 {
            if coalescer.add("x", now: 1.0 + Double(index) * 0.004) != nil { updates += 1 }
        }
        #expect(updates < 60, "500 tokens in two seconds must not mean 500 screen updates")
    }
}
