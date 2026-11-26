import SwiftUI
import Testing
@testable import AnyRouter

/// A picker row keeps two short lines at normal sizes and wraps at accessibility sizes, so the name is never cut.
struct RowLayoutTests {
    @Test func onlyAccessibilitySizesStackTheRow() {
        for size in DynamicTypeSize.allCases {
            #expect(RowLayout.make(size).isStacked == size.isAccessibilitySize, "\(size)")
        }
    }

    @Test func normalSizesKeepTwoSingleLines() {
        for size in [DynamicTypeSize.xSmall, .large, .xxxLarge] {
            #expect(RowLayout.make(size) == .compact)
        }
        #expect(RowLayout.compact.titleLineLimit == 1)
        #expect(RowLayout.compact.detailLineLimit == 1)
    }

    @Test func atAccessibility3TheNameAndEveryDetailWrapInsteadOfTruncating() {
        let layout = RowLayout.make(.accessibility3)
        #expect(layout.isStacked)
        #expect(layout.titleLineLimit == nil, "no line limit: the whole name shows")
        #expect(layout.detailLineLimit == nil)
        let long = "Nemotron 3.5 Super VL 120B A12B Instruct Reasoning Edition"
        #expect(PickerRow.make(cloudModel("nvidia/long", name: long)).title == long, "the row model never shortens the name")
    }
}
