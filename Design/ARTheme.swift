import SwiftUI

/// Layout and type tokens: 10pt corner radius and a 16pt base font.
enum ARTheme {
    static let radius: CGFloat = 10
    static let radiusSmall: CGFloat = 6
    static let radiusMedium: CGFloat = 8
    static let radiusLarge: CGFloat = 14
    static let radiusXL: CGFloat = 24
    static let pagePadding: CGFloat = 16
    static let sidebarWidth: CGFloat = 300
    static let controlSize: CGFloat = 40
    static let contentMaxWidth: CGFloat = 768
}

extension Font {
    /// The app uses the system font (SF Pro) so text follows Dynamic Type.
    static let arXS = Font.system(size: 12)
    static let arSM = Font.system(size: 14)
    static let arBase = Font.system(size: 16)
    static let arLG = Font.system(size: 18)
    static let arXL = Font.system(size: 20, weight: .semibold)
    static let arTitle = Font.system(size: 24, weight: .semibold)
    static let arHero = Font.system(size: 30, weight: .semibold)
}

extension View {
    /// Bordered rounded surface used for cards (card).
    func arCard(fill: Color = ARColor.card, radius: CGFloat = ARTheme.radiusLarge) -> some View {
        background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(ARColor.border, lineWidth: 1))
    }
}
