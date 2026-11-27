import SwiftUI

/// When the chat list follows a streaming reply. It follows while the reader is at the bottom and lets go
/// the moment they touch the list; it picks up again when they scroll back to the bottom.
///
/// "At the bottom" is whether the list's end marker is on screen (`onScrollVisibilityChange`), not offset arithmetic.
/// The arithmetic (offset plus container against content plus the bottom inset) is the only input that could keep the
/// jump button up at rest at the bottom, and it did: with the composer, its chips and the keyboard under the list, its
/// idea of the bottom and the real one differ, so the button stayed and following never came back.
enum ScrollFollow {
    /// The follow state after a scroll phase change. Only the reader's own gestures change it: content growth
    /// and our own scrolling (phase animating or idle after it) keep the state.
    static func following(from old: ScrollPhase, to new: ScrollPhase, atBottom: Bool, was following: Bool) -> Bool {
        switch new {
        case .tracking, .interacting:
            return false
        case .idle:
            return old == .decelerating || old == .interacting || old == .tracking ? atBottom : following
        default:
            return following
        }
    }

    /// The jump-to-latest button: only when the end of the list is off screen and the list is not following on its own.
    static func showsJumpButton(following: Bool, atBottom: Bool) -> Bool { !following && !atBottom }

    /// What moved the list (decision D27).
    enum Event: Equatable {
        /// Messages were added or removed. `lastIsQuestion`: the newest message is the person's, its reply not started yet.
        case messagesChanged(isStreaming: Bool, lastIsQuestion: Bool)
        case streamStarted
        case streamEnded
    }

    /// Where the list goes after an event.
    enum Settle: Equatable {
        /// A send or a regenerate: the person's question goes to the top of the view and the reply grows under it.
        case question(UUID)
        /// A thread opened or a reply was removed: the end of the list, following.
        case bottom
        /// A reply ended: the reader stays where they are reading.
        case stay
    }

    static func settle(after event: Event, lastQuestionID: UUID?) -> Settle {
        switch event {
        case .streamEnded:
            return .stay
        case .streamStarted:
            return lastQuestionID.map(Settle.question) ?? .bottom
        case .messagesChanged(let isStreaming, let lastIsQuestion):
            // A send adds the question before the stream starts: settle on it once, not on the end first.
            guard isStreaming || lastIsQuestion, let lastQuestionID else { return .bottom }
            return .question(lastQuestionID)
        }
    }

    /// The least height of the last row, so that the question above it can sit at the top of the visible area with the
    /// list's end marker still on screen. `visible` is the list's height without the bars over it; `question` is the
    /// height of the question row, nil when the last row is the question itself; `trailing` is what follows the last row
    /// (spacing, the end marker, the bottom padding).
    static func lastRowMinHeight(visible: CGFloat, question: CGFloat?, spacing: CGFloat, trailing: CGFloat) -> CGFloat {
        guard let question else { return max(0, visible - trailing) }
        return max(0, visible - question - spacing - trailing)
    }
}
