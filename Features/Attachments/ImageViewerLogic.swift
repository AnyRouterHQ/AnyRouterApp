import CoreGraphics
import Foundation

/// The numbers behind the full-screen photo viewer: how far it zooms, what a double tap does, and when a pull dismisses it.
enum ImageZoom {
    static let minimumScale: CGFloat = 1
    static let maximumScale: CGFloat = 5
    static let doubleTapScale: CGFloat = 2.5
    /// A pull this far (points) past the edge, with the photo not zoomed in, closes the viewer.
    static let dismissDistance: CGFloat = 90

    /// A double tap zooms in, or back out when the photo is already zoomed.
    static func doubleTapTarget(current: CGFloat) -> CGFloat {
        current > minimumScale + 0.01 ? minimumScale : doubleTapScale
    }

    /// The part of the photo (in its own coordinates) that fills the screen when zoomed to `scale` around `center`.
    static func zoomRect(center: CGPoint, scale: CGFloat, size: CGSize) -> CGRect {
        let width = size.width / scale
        let height = size.height / scale
        return CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
    }

    /// Pulling a zoomed-in photo moves it; only a photo at its normal size is dismissed by the pull.
    static func shouldDismiss(pull: CGFloat, scale: CGFloat) -> Bool {
        scale <= minimumScale + 0.01 && abs(pull) >= dismissDistance
    }

    /// The backdrop fades while the photo is pulled away, never fully.
    static func backdropOpacity(pull: CGFloat) -> Double {
        max(0.3, 1 - Double(abs(pull)) / 400)
    }
}
