import XCTest

/// A reply's Select Text button opens the whole reply as one selectable text, so any part of it can be copied.
@MainActor
final class SelectTextTests: XCTestCase {
    func testSelectTextOpensASelectableTextAndDoneClosesIt() {
        let app = XCUIApplication()
        app.launchArguments = ["-ARDemoData", "YES", "-ARDemoTools", "YES"]
        app.launch()

        let thread = app.staticTexts["Latest Swift news"]
        app.revealSidebar(whenVisible: thread)
        let tappable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: thread)
        XCTAssertEqual(XCTWaiter().wait(for: [tappable], timeout: 10), .completed, "the thread row never became tappable")
        thread.tap()

        let select = app.buttons.matching(identifier: "reply.select-text").firstMatch
        XCTAssertTrue(select.waitForExistence(timeout: 10), "a finished reply offers Select Text")
        select.tap()

        let text = app.textViews["select-text.view"]
        XCTAssertTrue(text.waitForExistence(timeout: 5), "the sheet shows the reply as a text view")
        XCTAssertFalse((text.value as? String ?? "").isEmpty, "with the reply's words in it")
        text.press(forDuration: 1.0)
        XCTAssertTrue(app.menuItems["Copy"].waitForExistence(timeout: 3) || app.menuItems["Select"].exists
                      || app.menuItems["Select All"].exists, "a long press offers selection")

        app.buttons["select-text.done"].tap()
        XCTAssertTrue(text.waitForNonExistence(timeout: 5), "Done closes the sheet")
    }
}
