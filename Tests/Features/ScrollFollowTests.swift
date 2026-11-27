import SwiftUI
import Testing
@testable import AnyRouter

struct ScrollFollowTests {
    @Test func touchingTheListStopsFollowing() {
        #expect(!ScrollFollow.following(from: .idle, to: .tracking, atBottom: true, was: true))
        #expect(!ScrollFollow.following(from: .tracking, to: .interacting, atBottom: true, was: true))
    }

    /// The operator's bug: scrolled back to the bottom by hand, the list follows again, so the button goes away.
    @Test func settlingAtTheBottomAfterAGestureFollowsAgainAndHidesTheButton() {
        for old in [ScrollPhase.decelerating, .interacting, .tracking] {
            let following = ScrollFollow.following(from: old, to: .idle, atBottom: true, was: false)
            #expect(following)
            #expect(!ScrollFollow.showsJumpButton(following: following, atBottom: true))
        }
        #expect(!ScrollFollow.following(from: .decelerating, to: .idle, atBottom: false, was: false))
    }

    /// Our own scrollTo ends idle too, and growth may have moved the bottom away already: no change.
    @Test func idleAfterOurOwnScrollKeepsTheState() {
        #expect(ScrollFollow.following(from: .animating, to: .idle, atBottom: false, was: true))
        #expect(!ScrollFollow.following(from: .idle, to: .animating, atBottom: true, was: false))
    }

    @Test func theJumpButtonShowsOnlyWhenTheEndIsOffScreenAndNothingFollows() {
        #expect(ScrollFollow.showsJumpButton(following: false, atBottom: false))
        #expect(!ScrollFollow.showsJumpButton(following: false, atBottom: true), "at the bottom it never shows")
        #expect(!ScrollFollow.showsJumpButton(following: true, atBottom: false), "following: the list scrolls itself")
        #expect(!ScrollFollow.showsJumpButton(following: true, atBottom: true))
    }
}
