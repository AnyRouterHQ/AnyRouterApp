import SwiftUI

/// Layout tokens. Type uses the system text styles, so Dynamic Type works.
enum ARTheme {
    static let radius: CGFloat = 10
    static let radiusLarge: CGFloat = 14
    static let radiusXL: CGFloat = 24
    static let pagePadding: CGFloat = 16
    /// The chat column on a wide screen, margins included, so a line stays readable on an iPad.
    static let contentMaxWidth: CGFloat = 720
    /// One control size for rows and hand-made glass circles: the HIG's 44 pt target. Read it through `@ScaledMetric`.
    static let controlSize: CGFloat = 44
    /// The composer row: the one-line field and the + beside it. Read it through `@ScaledMetric`.
    static let composerRowHeight: CGFloat = 48
}

extension View {
    /// Centers the content in a column no wider than `ARTheme.contentMaxWidth`, like the readable content guide.
    /// Below that width it is just the page margins.
    func readableWidth() -> some View {
        padding(.horizontal, ARTheme.pagePadding)
            .frame(maxWidth: ARTheme.contentMaxWidth)
            .frame(maxWidth: .infinity)
    }
}
