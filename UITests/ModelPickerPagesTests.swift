import XCTest

/// Two model picker states no other flow reaches: signed out, the AnyRouter tab lists nothing usable and puts every model under Not available, and a router's
/// detail page opens the list of models it routes to (its content comes from the network, so only the sheet is checked).
@MainActor
final class ModelPickerPagesTests: XCTestCase {
    private func openPicker(_ app: XCUIApplication) -> XCUIElement {
        let title = app.buttons["Model"]
        XCTAssertTrue(title.waitForExistence(timeout: 15))
        title.tap()
        let tabs = app.segmentedControls.firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 5), "the picker opened")
        return tabs
    }

    func testSignedOutEveryCloudModelIsUnderNotAvailableWithASignInReason() {
        let app = XCUIApplication.launchedOnDemoData(extra: ["-ARDemoSignedOut", "YES"])
        let tabs = openPicker(app)
        tabs.buttons["AnyRouter"].tap()
        XCTAssertTrue(app.buttons["model-picker.sign-in"].waitForExistence(timeout: 10), "the tab offers sign in")
        XCTAssertFalse(app.buttons["model-row.anyrouter/openai/gpt-5"].exists, "nothing is usable signed out")
        let notAvailable = app.buttons["model-picker.not-available"]
        XCTAssertTrue(notAvailable.waitForExistence(timeout: 5))
        notAvailable.tap()
        let row = app.buttons["unavailable-row.anyrouter/openai/gpt-5"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "GPT-5 is listed as not available")
        XCTAssertTrue(row.label.contains("Sign in to use"), "with the reason: \(row.label)")
        row.tap()
        XCTAssertTrue(app.buttons["cloud-signin.sign-in"].waitForExistence(timeout: 5), "tapping offers the sign-in sheet")
    }

    func testARouterDetailOpensTheModelsItRoutesTo() {
        let app = XCUIApplication.launchedOnDemoData()
        let tabs = openPicker(app)
        tabs.buttons["AnyRouter"].tap()
        let row = app.buttons["model-row.anyrouter/anyrouter/auto"]
        XCTAssertTrue(row.waitForExistence(timeout: 10), "AnyRouter Auto is listed")
        row.swipeLeft()
        let details = app.buttons["Details"].firstMatch
        XCTAssertTrue(details.waitForExistence(timeout: 5), "a swipe shows Details")
        details.tap()
        let routing = app.buttons["Models it routes to"]
        XCTAssertTrue(routing.waitForExistence(timeout: 10), "a router's page links to the models it picks from")
        routing.tap()
        let done = app.buttons["Done"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 10), "the routing sheet opened")
        done.tap()
        XCTAssertTrue(done.waitForNonExistence(timeout: 5), "Done closes the routing sheet")
    }
}
