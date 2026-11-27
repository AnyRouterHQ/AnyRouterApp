import UIKit

/// A logo asset drawn at the size it is shown. A picker or a menu keeps only the image and the text of a label and drops
/// their frames, so a vector logo at its own size (the brand mark is hundreds of points wide) filled the whole Decisions
/// sheet. Drawn at the slot's size, the image fits the slot wherever it lands.
@MainActor
enum LogoImage {
    private static var cache: [String: UIImage] = [:]

    /// `side` is the longest side in points. Nil when the app has no image by that name.
    static func make(_ name: String, side: CGFloat, template: Bool) -> UIImage? {
        let key = "\(name)|\(Int((side * 4).rounded()))|\(template)"
        if let hit = cache[key] { return hit }
        guard let source = UIImage(named: name), source.size.width > 0, source.size.height > 0 else { return nil }
        let scale = side / max(source.size.width, source.size.height)
        let size = CGSize(width: source.size.width * scale, height: source.size.height * scale)
        let drawn = UIGraphicsImageRenderer(size: size).image { _ in source.draw(in: CGRect(origin: .zero, size: size)) }
        let image = drawn.withRenderingMode(template ? .alwaysTemplate : .alwaysOriginal)
        cache[key] = image
        return image
    }
}
