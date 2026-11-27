import XCTest

/// The Apps list and the custom decision from the sidebar, on demo data (no network). The Run button follows the form.
@MainActor
final class DecisionsTests: XCTestCase {
    private func openApps(_ app: XCUIApplication) {
        // iPhone: the sidebar is a drawer behind the menu button. iPad: a column, open in landscape only.
        let row = app.buttons["sidebar-apps"]
        app.revealSidebar(whenVisible: row)
        row.tap()
        XCTAssertTrue(app.navigationBars["Apps"].waitForExistence(timeout: 10))
    }

    func testTheAppsListEndsWithTheCustomDecision() {
        let app = XCUIApplication()
        app.launchArguments = ["-ARDemoData", "YES"]
        app.launch()
        openApps(app)
        XCTAssertTrue(app.buttons["apps-tile-scam-check"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["apps-tile-custom"].exists)
    }

    func testAnAppRunsFromAPastedTextAndAnswersInAWord() {
        let app = XCUIApplication()
        app.launchArguments = ["-ARDemoData", "YES"]
        app.launch()
        openApps(app)
        app.buttons["apps-tile-email-triage"].tap()
        XCTAssertTrue(app.navigationBars["Email triage"].waitForExistence(timeout: 10))
        let run = app.buttons["decisions-run"]
        XCTAssertTrue(run.waitForExistence(timeout: 5))
        XCTAssertFalse(run.isEnabled, "Run needs something to judge")

        let sample = app.buttons["decisions-sample-Needs a reply"]
        XCTAssertTrue(sample.waitForExistence(timeout: 5))
        sample.tap()
        XCTAssertTrue(run.isEnabled)
        run.tap()
        XCTAssertTrue(app.descendants(matching: .any)["decisions-result-line"].waitForExistence(timeout: 10))
    }

    func testAddingAYesNoQuestionEnablesRunInTheCustomDecision() {
        let app = XCUIApplication()
        app.launchArguments = ["-ARDemoData", "YES"]
        app.launch()
        openApps(app)
        app.buttons["apps-tile-custom"].tap()
        XCTAssertTrue(app.navigationBars["Custom decision"].waitForExistence(timeout: 10))
        let run = app.buttons["decisions-run"]
        XCTAssertTrue(run.waitForExistence(timeout: 5))
        XCTAssertFalse(run.isEnabled, "Run needs text and a question")

        let state = app.descendants(matching: .any)["decisions-state"]
        state.tap()
        state.typeText("Please refund my order today")

        let add = app.buttons["decisions-add-question"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        app.buttons["Yes/No"].tap()

        let prompt = app.descendants(matching: .any)["decisions-question-prompt"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 5))
        prompt.tap()
        prompt.typeText("Is this urgent?")

        XCTAssertTrue(run.waitForExistence(timeout: 5))
        XCTAssertTrue(run.isEnabled)
    }
}
