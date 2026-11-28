import XCTest

/// Two model picker states no other flow reaches: signed out, the AnyRouter tab says there are no cloud models, and a router's
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

    func testSignedOutTheAnyRouterTabHasNoCloudModels() {
        let app = XCUIApplication.launchedOnDemoData(extra: ["-ARDemoSignedOut", "YES"])
        let tabs = openPicker(app)
        tabs.buttons["AnyRouter"].tap()
        XCTAssertTrue(app.labelled(containing: "No cloud models").waitForExistence(timeout: 10), "an empty AnyRouter list says so")
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
