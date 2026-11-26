import XCTest

/// The model pill opens the picker; picking a model changes the pill. Uses demo data.
@MainActor
final class ModelPickerTests: XCTestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ARDemoData", "YES"]
        app.launch()
        return app
    }

    func testAnyRouterTabPickChangesThePill() {
        let app = launch()
        let pill = app.buttons["Model"]
        XCTAssertTrue(pill.waitForExistence(timeout: 15))
        XCTAssertTrue(pill.images["model-logo"].exists, "the pill shows a logo next to the name")
        pill.tap()

        let tabs = app.segmentedControls.firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 5))
        tabs.buttons["AnyRouter"].tap()
        let row = app.buttons["model-row.anyrouter/openai/gpt-5"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()

        XCTAssertTrue(app.buttons["Model"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["Model"].value as? String, "GPT-5")
    }

    func testLocalTabListsDownloadedModelsAndBrowse() {
        let app = launch()
        XCTAssertTrue(app.buttons["Model"].waitForExistence(timeout: 15))
        app.buttons["Model"].tap()
        XCTAssertTrue(app.segmentedControls.firstMatch.waitForExistence(timeout: 5))
        app.segmentedControls.firstMatch.buttons["Local"].tap()
        XCTAssertTrue(app.buttons["Browse models"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["model-row.apple/foundation"].exists)
    }
}
