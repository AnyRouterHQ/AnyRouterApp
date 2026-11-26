import SwiftUI
import Testing
@testable import AnyRouter

struct ScrollFollowTests {
    @Test func nearBottomUsesTheInsetAndATolerance() {
        // Content 1000 tall, container 600, inset 80: the bottom offset is 480.
        #expect(ScrollFollow.isNearBottom(offset: 480, container: 600, content: 1000, bottomInset: 80))
        #expect(ScrollFollow.isNearBottom(offset: 400, container: 600, content: 1000, bottomInset: 80))
        #expect(!ScrollFollow.isNearBottom(offset: 200, container: 600, content: 1000, bottomInset: 80))
    }

    @Test func touchingTheListStopsFollowing() {
        #expect(!ScrollFollow.following(from: .idle, to: .tracking, nearBottom: true, was: true))
        #expect(!ScrollFollow.following(from: .tracking, to: .interacting, nearBottom: true, was: true))
    }

    @Test func settlingAtTheBottomAfterAGestureFollowsAgain() {
        #expect(ScrollFollow.following(from: .decelerating, to: .idle, nearBottom: true, was: false))
        #expect(!ScrollFollow.following(from: .decelerating, to: .idle, nearBottom: false, was: false))
    }

    /// Our own scrollTo ends idle too, and growth may have moved the bottom away already: no change.
    @Test func idleAfterOurOwnScrollKeepsTheState() {
        #expect(ScrollFollow.following(from: .animating, to: .idle, nearBottom: false, was: true))
        #expect(!ScrollFollow.following(from: .idle, to: .animating, nearBottom: true, was: false))
    }

    @Test func theJumpButtonShowsOnlyWhenMoreThanAboutOneRowIsOffScreen() {
        // Content 1000 tall, container 600, inset 80: at the bottom the offset is 480.
        let atBottom = ScrollFollow.distanceFromBottom(offset: 480, container: 600, content: 1000, bottomInset: 80)
        #expect(atBottom == 0)
        #expect(!ScrollFollow.showsJumpButton(distance: atBottom))
        let slightlyUp = ScrollFollow.distanceFromBottom(offset: 400, container: 600, content: 1000, bottomInset: 80)
        #expect(!ScrollFollow.showsJumpButton(distance: slightlyUp))
        let wellUp = ScrollFollow.distanceFromBottom(offset: 200, container: 600, content: 1000, bottomInset: 80)
        #expect(ScrollFollow.showsJumpButton(distance: wellUp))
    }
}
