import CoreGraphics
import SwiftUI

/// When the chat list follows a streaming reply. It follows while the reader is at the bottom and lets go
/// the moment they touch the list; it picks up again when they scroll back to the bottom.
enum ScrollFollow {
    /// Distance from the bottom that still counts as "at the bottom": one flush can add a few lines before we scroll.
    static let tolerance: CGFloat = 120

    static func isNearBottom(offset: CGFloat, container: CGFloat, content: CGFloat, bottomInset: CGFloat) -> Bool {
        offset + container >= content + bottomInset - tolerance
    }

    /// The follow state after a scroll phase change. Only the reader's own gestures change it: content growth
    /// and our own scrolling (phase animating or idle after it) keep the state.
    static func following(from old: ScrollPhase, to new: ScrollPhase, nearBottom: Bool, was following: Bool) -> Bool {
        switch new {
        case .tracking, .interacting:
            return false
        case .idle:
            return old == .decelerating || old == .interacting || old == .tracking ? nearBottom : following
        default:
            return following
        }
    }
}
