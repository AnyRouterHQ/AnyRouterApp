import Testing
@testable import AnyRouter

struct HomeTipsTests {
    /// Cycles through fixed values so the test is deterministic.
    struct Sequence: RandomNumberGenerator {
        var values: [UInt64]
        var i = 0
        mutating func next() -> UInt64 { defer { i += 1 }; return values[i % values.count] }
    }

    @Test func listIsSmallFriendlyAndUnique() {
        #expect(HomeTips.all.count >= 25)
        #expect(Set(HomeTips.all).count == HomeTips.all.count)
        #expect(HomeTips.all.allSatisfy { !$0.isEmpty && $0.count <= 70 })
    }

    @Test func neverRepeatsTheCurrentLine() {
        var generator = Sequence(values: [0, 1, 2, 3, 5, 8, 13])
        var current: String? = HomeTips.all[0]
        for _ in 0..<500 {
            let next = HomeTips.next(after: current, using: &generator)
            #expect(next != current)
            current = next
        }
    }

    @Test func aSubtitleThatIsNotATipStillGetsATip() {
        #expect(HomeTips.all.contains(HomeTips.next(after: "Using Apple Intelligence · on device")))
    }
}
