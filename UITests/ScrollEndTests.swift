import XCTest

/// "Scroll to bottom not working" (operator): a long chat opens at its end, and the jump arrow brings the end into view
/// and goes away. The end is the last reply's footer (Regenerate shows only there) sitting above the composer. With a
/// LazyVStack the jump landed on estimated row heights and the last row was not even laid out (bisect 46129022686).
@MainActor
final class ScrollEndTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ARDemoData", "YES", "-ARDemoLongThread", "40"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["chat.content"].waitForExistence(timeout: 20), "the long chat opens")
        return app
    }

    private func assertAtTheEnd(_ app: XCUIApplication, _ what: String) {
        sleep(2)
        let end = app.buttons["reply.regenerate"]
        let input = app.descendants(matching: .any)["composer.input"]
        XCTAssertTrue(end.waitForExistence(timeout: 5), "\(what): the last reply's footer exists")
        XCTAssertTrue(end.isHittable, "\(what): the last reply's footer is on screen, not under the composer (footer \(end.frame), field \(input.frame))")
        XCTAssertLessThanOrEqual(end.frame.maxY, input.frame.minY, "\(what): the end sits above the composer")
        XCTAssertFalse(app.buttons["jump-to-latest"].exists, "\(what): no jump arrow at the end")
    }

    func testALongChatOpensAtItsEnd() {
        assertAtTheEnd(launch(), "open at launch")
    }

    func testTheJumpArrowBringsTheEnd() {
        let app = launch()
        for _ in 0..<3 { app.swipeDown() }
        let jump = app.buttons["jump-to-latest"]
        XCTAssertTrue(jump.waitForExistence(timeout: 5), "the arrow shows away from the end")
        jump.tap()
        assertAtTheEnd(app, "after the jump arrow")
    }

    func testOpeningFromTheSidebarLandsAtTheEnd() {
        let app = launch()
        let other = app.staticTexts["Explain Swift actors"]
        app.revealSidebar(whenVisible: other)
        other.tap()
        let long = app.staticTexts["Long thread"]
        app.revealSidebar(whenVisible: long)
        long.tap()
        assertAtTheEnd(app, "opened from the sidebar")
    }
}
