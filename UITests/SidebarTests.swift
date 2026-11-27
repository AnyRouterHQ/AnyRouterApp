import UIKit
import XCTest

/// The sidebar: an open drawer leaves the chat untouched, the bottom bar, View all and Decisions (demo data).
@MainActor
final class SidebarTests: XCTestCase {
    private func launch() -> XCUIApplication { .launchedOnDemoData(appearance: "light") }

    /// Average of red, green and blue (0 black, 1 white) of the screen pixel at a point in window coordinates.
    private func brightness(_ app: XCUIApplication, x: CGFloat, y: CGFloat) throws -> CGFloat {
        let image = app.screenshot().image
        let cg = try XCTUnwrap(image.cgImage)
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = try XCTUnwrap(CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(cg, in: CGRect(x: -x * image.scale, y: -(CGFloat(cg.height) - y * image.scale) , width: CGFloat(cg.width), height: CGFloat(cg.height)))
        return (CGFloat(pixel[0]) + CGFloat(pixel[1]) + CGFloat(pixel[2])) / (3 * 255)
    }

    func testOpenDrawerLeavesTheChatUndimmed() throws {
        let app = launch()
        try XCTSkipIf(!app.buttons["Menu"].waitForExistence(timeout: 15), "iPad layout: the sidebar is a column")
        XCTAssertTrue(app.element("home.greeting").waitForExistence(timeout: 10))
        let width = app.windows.firstMatch.frame.width
        let height = app.windows.firstMatch.frame.height
        let shift = min(width - 64, 360)
        let heights: [CGFloat] = [0.3, 0.4, 0.5]
        // A point in the chat's left margin, while the drawer is closed.
        let before = try heights.map { try brightness(app, x: width - 16 - shift, y: height * $0) }

        app.buttons["Menu"].tap()
        XCTAssertTrue(app.element("sidebar.header").waitForExistence(timeout: 5))
        sleep(1)
        // The same point of the chat, now shifted into the strip beside the drawer.
        let after = try heights.map { try brightness(app, x: width - 16, y: height * $0) }
        for (was, now) in zip(before, after) {
            XCTAssertEqual(now, was, accuracy: 0.03, "the chat beside the drawer keeps its colors: no dim, no blur")
        }
        XCTAssertEqual(app.searchFields.count, 0, "the sidebar has no inline search field")
    }

    func testSettingsButtonOpensSettings() {
        let app = launch()
        let gear = app.buttons["sidebar.settings"]
        app.revealSidebar(whenVisible: gear)
        gear.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
    }

    func testNewChatCreatesAThreadOnFirstSend() {
        let app = launch()
        let compose = app.buttons["sidebar.compose"]
        app.revealSidebar(whenVisible: compose)
        compose.tap()
        let input = app.element(UITestIDs.composerInput)
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.tap()
        input.typeText("hello from the sidebar")
        app.buttons["Send"].tap()
        XCTAssertTrue(app.buttons["Voice input"].waitForExistence(timeout: 20), "the reply finished")

        let sidebar = app.element(UITestIDs.sidebarHeader)
        if !sidebar.isHittable { app.revealSidebar(whenVisible: sidebar) }
        XCTAssertTrue(app.collectionViews.staticTexts["hello from the sidebar"].waitForExistence(timeout: 5), "the new chat is listed")
    }

    func testViewAllOpensTheSearchWithEveryChat() {
        let app = launch()
        let viewAll = app.buttons["sidebar.viewall"]
        app.revealSidebar(whenVisible: viewAll)
        viewAll.tap()
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Dinner with chickpeas'")).firstMatch.waitForExistence(timeout: 5))
    }

    /// The drawer reads as a compact list: 44 pt chat rows, no tall gap before a section title, and a New chat button
    /// no taller than the gear beside it (both were bigger, the operator called it out).
    func testRowsAreCompactAndBarButtonsMatch() {
        let app = launch()
        let gear = app.buttons["sidebar.settings"]
        app.revealSidebar(whenVisible: gear)
        let compose = app.buttons["sidebar.compose"]
        XCTAssertEqual(compose.frame.height, gear.frame.height, accuracy: 1, "New chat is as tall as the gear")
        XCTAssertLessThanOrEqual(compose.frame.height, 48, "a 40 pt glass capsule in a 44 pt hit area")

        let list = app.collectionViews.firstMatch
        let first = list.staticTexts["Explain Swift actors"], second = list.staticTexts["Switch models in a chat"]
        XCTAssertTrue(first.waitForExistence(timeout: 5) && second.exists, "the demo chats are listed")
        XCTAssertEqual(second.frame.midY - first.frame.midY, 44, accuracy: 2, "chat rows are 44 pt")

        let pinned = list.staticTexts["Trip ideas for Lisbon"], recents = list.staticTexts["Recents"]
        XCTAssertTrue(pinned.exists && recents.exists)
        XCTAssertLessThan(recents.frame.midY - pinned.frame.midY, 70, "a section title follows the last row closely")
    }

    func testMoreHoldsDecisions() {
        let app = launch()
        let row = app.buttons["sidebar-decisions"]
        app.revealSidebar(whenVisible: row)
        row.tap()
        XCTAssertTrue(app.navigationBars["Decisions"].waitForExistence(timeout: 10))
    }
}
