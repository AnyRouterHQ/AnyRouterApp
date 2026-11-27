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
}
