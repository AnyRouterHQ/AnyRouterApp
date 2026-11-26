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

    func testOpeningTheDrawerHidesTheKeyboard() throws {
        let app = launch()
        try XCTSkipIf(!app.buttons["Menu"].waitForExistence(timeout: 10), "iPad layout: the sidebar is a column")
        let input = element(app, "composer.input")
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.tap()
        XCTAssertTrue(waitForKeyboard(app, present: true), "composer keyboard")

        app.buttons["Menu"].tap()
        XCTAssertTrue(element(app, "sidebar.header").waitForExistence(timeout: 5))
        XCTAssertTrue(waitForKeyboard(app, present: false), "opening the drawer ends editing")
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
