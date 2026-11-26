import SwiftUI

/// Layout tokens. Type uses the system text styles, so Dynamic Type works.
enum ARTheme {
    static let radius: CGFloat = 10
    static let radiusLarge: CGFloat = 14
    static let radiusXL: CGFloat = 24
    static let pagePadding: CGFloat = 16
    static let contentMaxWidth: CGFloat = 768
}

extension View {
    /// Bordered rounded surface used for cards (card).
    func arCard(fill: Color = ARColor.card, radius: CGFloat = ARTheme.radiusLarge) -> some View {
        background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(ARColor.border, lineWidth: 1))
    }
}
