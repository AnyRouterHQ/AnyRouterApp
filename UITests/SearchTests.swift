import XCTest

/// The full-screen chat search behind the sidebar's "Search chats" row (demo data).
@MainActor
final class SearchTests: XCTestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ARDemoData", "YES"]
        app.launch()
        return app
    }

    private func openSearch(_ app: XCUIApplication) -> XCUIElement {
        let row = app.buttons["sidebar.search"]
        app.revealSidebar(whenVisible: row)
        row.tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "the search screen opens")
        return field
    }

    func testSearchOpensFocusedAndAResultOpensTheChat() {
        let app = launch()
        let field = openSearch(app)
        let focused = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hasKeyboardFocus == true"), object: field)
        XCTAssertEqual(XCTWaiter().wait(for: [focused], timeout: 10), .completed, "the field has focus without a tap")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "the keyboard is up")

        field.typeText("lisbon")
        let result = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Trip ideas for Lisbon")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Rust or Go")).firstMatch.exists, "non-matches are gone")
        result.tap()

        XCTAssertFalse(app.searchFields.firstMatch.waitForExistence(timeout: 2), "the search screen closes")
        let chat = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", "relaxed 3 day plan")).firstMatch
        XCTAssertTrue(chat.waitForExistence(timeout: 10), "the chat shows the picked conversation")
    }

    func testCloseButtonReturnsToTheSidebar() {
        let app = launch()
        _ = openSearch(app)
        app.buttons["search.close"].tap()
        XCTAssertTrue(app.buttons["sidebar.search"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.searchFields.firstMatch.exists)
    }

    func testNoMatchShowsTheSystemEmptyState() {
        let app = launch()
        let field = openSearch(app)
        field.typeText("qqqzzz")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "No Results")).firstMatch.waitForExistence(timeout: 5))
    }
}
