import XCTest

/// Keyboard behavior around the sidebar drawer and tap-outside dismissal (demo data, iPhone layout).
@MainActor
final class KeyboardTests: XCTestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ARDemoData", "YES"]
        app.launch()
        return app
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func waitForKeyboard(_ app: XCUIApplication, present: Bool, timeout: TimeInterval = 5) -> Bool {
        let predicate = NSPredicate(format: "count \(present ? ">" : "==") 0")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: app.keyboards)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    func testOpeningTheDrawerHidesTheKeyboardAndSearchTapShowsIt() throws {
        let app = launch()
        try XCTSkipIf(!app.buttons["Menu"].waitForExistence(timeout: 10), "iPad layout: the sidebar is a column")
        let input = element(app, "composer.input")
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.tap()
        XCTAssertTrue(waitForKeyboard(app, present: true), "composer keyboard")

        app.buttons["Menu"].tap()
        XCTAssertTrue(element(app, "sidebar.header").waitForExistence(timeout: 5))
        XCTAssertTrue(waitForKeyboard(app, present: false), "opening the drawer ends editing")

        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        XCTAssertTrue(waitForKeyboard(app, present: true), "tapping search shows the keyboard")

        // The chat keeps the full screen height while the drawer and the keyboard are both up.
        let main = element(app, "main.container")
        XCTAssertTrue(main.exists)
        XCTAssertEqual(main.frame.height, app.windows.firstMatch.frame.height, accuracy: 1)

        element(app, "sidebar.header").tap()
        XCTAssertTrue(waitForKeyboard(app, present: false), "tapping the header hides the keyboard")
    }

    func testTapOutsideTheComposerHidesTheKeyboard() throws {
        let app = launch()
        let input = element(app, "composer.input")
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.tap()
        XCTAssertTrue(waitForKeyboard(app, present: true))
        element(app, "home.subtitle").tap()
        XCTAssertTrue(waitForKeyboard(app, present: false), "a tap on the home text hides the keyboard")
    }

    func testTypingInTheComposerDoesNotDismissItself() throws {
        let app = launch()
        let input = element(app, "composer.input")
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.tap()
        input.typeText("hello")
        input.tap()
        XCTAssertTrue(waitForKeyboard(app, present: true), "a tap on the field keeps the keyboard")
    }
}
