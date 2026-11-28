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
        XCTAssertTrue(app.buttons["apps-tile-email-triage"].waitForExistence(timeout: 5))
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

    func testDecideAboutThisCarriesTheComposerTextIntoTheCustomDecision() {
        let app = XCUIApplication()
        app.launchArguments = ["-ARDemoData", "YES"]
        app.launch()
        let input = app.descendants(matching: .any)["composer.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 15))
        input.tap()
        input.typeText("Should I reply today")
        XCTAssertTrue(app.buttons["Add"].waitForExistence(timeout: 5))
        app.buttons["Add"].tap()
        let item = app.buttons["composer.decide"]
        XCTAssertTrue(item.waitForExistence(timeout: 5), "Decide about this is in the + menu")
        item.tap()
        XCTAssertTrue(app.navigationBars["Custom decision"].waitForExistence(timeout: 10))
        let state = app.descendants(matching: .any)["decisions-state"]
        XCTAssertTrue(state.waitForExistence(timeout: 5))
        XCTAssertEqual(state.value as? String, "Should I reply today")
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
        XCTAssertTrue(state.waitForExistence(timeout: 5), "the text field opens the form")
        state.tap()
        state.typeText("Please refund my order today")

        // The keyboard covers the lower rows; scroll the form until Add question can take the tap.
        let add = app.buttons["decisions-add-question"]
        XCTAssertTrue(add.waitForExistence(timeout: 5), "the questions section has an Add question menu")
        var swipes = 0
        while !add.isHittable && swipes < 4 { app.swipeUp(); swipes += 1 }
        add.tap()
        let yesNo = app.buttons["Yes/No"]
        XCTAssertTrue(yesNo.waitForExistence(timeout: 5), "the menu offers a yes/no question")
        yesNo.tap()

        let prompt = app.descendants(matching: .any)["decisions-question-prompt"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 5), "the new question has a prompt field")
        swipes = 0
        while !prompt.isHittable && swipes < 4 { app.swipeUp(); swipes += 1 }
        prompt.tap()
        prompt.typeText("Is this urgent?")

        XCTAssertTrue(run.waitForExistence(timeout: 5), "Run stays at the bottom")
        XCTAssertTrue(run.isEnabled, "text and one written question are enough to run")
    }
}
