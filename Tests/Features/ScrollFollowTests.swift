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

    /// A send or a regenerate starts a stream: the question goes to the top. Opening a thread shows its end.
    @Test func aStreamingReplySettlesItsQuestionAtTheTop() {
        let question = UUID()
        #expect(ScrollFollow.settle(after: .streamStarted, lastQuestionID: question) == .question(question))
        #expect(ScrollFollow.settle(after: .streamStarted, lastQuestionID: nil) == .bottom)
        let opened = ScrollFollow.Event.messagesChanged(isStreaming: false, lastIsQuestion: false)
        #expect(ScrollFollow.settle(after: opened, lastQuestionID: question) == .bottom)
    }

    /// The question is added before the stream starts: the list goes to it once, never to the end first.
    @Test func aSentQuestionSettlesBeforeItsStreamStarts() {
        let question = UUID()
        let sent = ScrollFollow.Event.messagesChanged(isStreaming: false, lastIsQuestion: true)
        #expect(ScrollFollow.settle(after: sent, lastQuestionID: question) == .question(question))
        let replyAdded = ScrollFollow.Event.messagesChanged(isStreaming: true, lastIsQuestion: false)
        #expect(ScrollFollow.settle(after: replyAdded, lastQuestionID: question) == .question(question))
        #expect(ScrollFollow.settle(after: sent, lastQuestionID: nil) == .bottom)
    }

    /// The reader may be reading the answer from its top when it ends: nothing moves.
    @Test func theEndOfAReplyLeavesTheReaderWhereTheyAre() {
        #expect(ScrollFollow.settle(after: .streamEnded, lastQuestionID: UUID()) == .stay)
        #expect(ScrollFollow.settle(after: .streamEnded, lastQuestionID: nil) == .stay)
    }

    /// The last turn fills the view, so the question can reach the top even when the reply is one line, and the end
    /// marker after it stays on screen (else the jump button would show right after every send).
    @Test func theLastRowLeavesRoomForTheQuestionAtTheTop() {
        // 700 visible: question 60, spacing 20, last row 587, then 33 of spacing, marker and padding.
        #expect(ScrollFollow.lastRowMinHeight(visible: 700, question: 60, spacing: 20, trailing: 33) == 587)
        #expect(ScrollFollow.lastRowMinHeight(visible: 700, question: nil, spacing: 20, trailing: 33) == 667, "the question is the last row")
        #expect(ScrollFollow.lastRowMinHeight(visible: 50, question: 60, spacing: 20, trailing: 33) == 0)
        #expect(ScrollFollow.lastRowMinHeight(visible: -10, question: nil, spacing: 20, trailing: 33) == 0)
    }

    @Test func theJumpButtonShowsOnlyWhenTheEndIsOffScreenAndNothingFollows() {
        #expect(ScrollFollow.showsJumpButton(following: false, atBottom: false))
        #expect(!ScrollFollow.showsJumpButton(following: false, atBottom: true), "at the bottom it never shows")
        #expect(!ScrollFollow.showsJumpButton(following: true, atBottom: false), "following: the list scrolls itself")
        #expect(!ScrollFollow.showsJumpButton(following: true, atBottom: true))
    }
}
