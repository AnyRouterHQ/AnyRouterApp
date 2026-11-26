import SwiftUI

/// How a picker row is laid out at a text size. Pure, so it is tested without a view.
/// Up to the large sizes a row is two lines of one line each, so the list keeps one row height.
/// At accessibility sizes the row stacks and every text wraps, so nothing is cut off.
struct RowLayout: Equatable {
    /// Logo and name on top, then each detail on its own line.
    var isStacked: Bool
    /// `nil` lets the text wrap.
    var titleLineLimit: Int?
    var detailLineLimit: Int?

    static let compact = RowLayout(isStacked: false, titleLineLimit: 1, detailLineLimit: 1)
    static let stacked = RowLayout(isStacked: true, titleLineLimit: nil, detailLineLimit: nil)

    static func make(_ size: DynamicTypeSize) -> RowLayout {
        size.isAccessibilitySize ? .stacked : .compact
    }
}
