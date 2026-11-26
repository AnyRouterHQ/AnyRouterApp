import CoreGraphics

/// Pure geometry and thresholds for the iPhone sidebar drawer.
enum DrawerLogic {
    /// The chat keeps this much of the screen visible next to the open drawer.
    static let peek: CGFloat = 64
    static let maxWidth: CGFloat = 360
    /// A closed drawer opens only from a drag that starts this close to the left edge.
    static let edgeWidth: CGFloat = 24
    /// An open drawer closes from a drag that starts this close to its right edge, or beyond it.
    /// Drags inside the list are left to the row swipe actions.
    static let grabWidth: CGFloat = 32

    static func width(forScreen screenWidth: CGFloat) -> CGFloat {
        max(0, min(screenWidth - peek, maxWidth))
    }

    /// 0 closed ... 1 open, following the finger and clamped.
    static func progress(isOpen: Bool, drag: CGFloat, width: CGFloat) -> CGFloat {
        guard width > 0 else { return 0 }
        return min(max(((isOpen ? width : 0) + drag) / width, 0), 1)
    }

    /// Whether a drag that began at `startX` with this translation is a drawer drag at all.
    static func tracks(startX: CGFloat, translation: CGSize, isOpen: Bool, width: CGFloat) -> Bool {
        guard abs(translation.width) > abs(translation.height) else { return false }
        return isOpen ? startX >= width - grabWidth : startX <= edgeWidth
    }

    /// Where the drawer settles when the finger lifts. `predictedEnd` is the translation SwiftUI
    /// projects from the release velocity, so a short fling carries it past the halfway mark.
    static func shouldOpen(isOpen: Bool, predictedEnd: CGFloat, width: CGFloat) -> Bool {
        ((isOpen ? width : 0) + predictedEnd) > width / 2
    }
}
