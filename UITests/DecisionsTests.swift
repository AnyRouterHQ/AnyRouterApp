import XCTest

/// Decisions from the sidebar, on demo data (no network). The Run button follows the form.
@MainActor
final class DecisionsTests: XCTestCase {
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        var tries = 0
        while !element.isHittable && tries < 8 {
            app.swipeUp()
            tries += 1
        }
        XCTAssertTrue(element.isHittable)
    }

    func testAddingAYesNoQuestionEnablesRun() {
        let app = XCUIApplication()
        app.launchArguments = ["-ARDemoData", "YES"]
        app.launch()

        // iPhone: the sidebar is a drawer behind the menu button. iPad: it is open at launch.
        let row = app.buttons["sidebar-decisions"]
        if !row.waitForExistence(timeout: 2) {
            XCTAssertTrue(app.buttons["Menu"].waitForExistence(timeout: 10))
            app.buttons["Menu"].tap()
        }
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()

        XCTAssertTrue(app.navigationBars["Decisions"].waitForExistence(timeout: 10))
        let run = app.buttons["decisions-run"]
        XCTAssertTrue(run.waitForExistence(timeout: 5))
        XCTAssertFalse(run.isEnabled, "Run needs text and a question")

        let state = app.textViews["decisions-state"]
        state.tap()
        state.typeText("Please refund my order today")

        let add = app.buttons["decisions-add-question"]
        scrollTo(add, in: app)
        add.tap()

        let prompt = app.descendants(matching: .any)["decisions-question-prompt"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 5))
        scrollTo(prompt, in: app)
        prompt.tap()
        prompt.typeText("Is this urgent?")

        XCTAssertTrue(run.waitForExistence(timeout: 5))
        XCTAssertTrue(run.isEnabled)
    }
}
