import XCTest

/// The model title in the top bar opens the picker; picking a model changes the title. Uses demo data.
@MainActor
final class ModelPickerTests: XCTestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ARDemoData", "YES"]
        app.launch()
        return app
    }

    func testAnyRouterTabPickChangesTheTitle() {
        let app = launch()
        let title = app.buttons["Model"]
        XCTAssertTrue(title.waitForExistence(timeout: 15))
        title.tap()

        let tabs = app.segmentedControls.firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 5))
        tabs.buttons["AnyRouter"].tap()
        let row = app.buttons["model-row.anyrouter/openai/gpt-5"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()

        XCTAssertTrue(app.buttons["Model"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["Model"].value as? String, "GPT-5")
    }

    func testInfoButtonPushesTheModelDetail() {
        let app = launch()
        XCTAssertTrue(app.buttons["Model"].waitForExistence(timeout: 15))
        app.buttons["Model"].tap()
        let tabs = app.segmentedControls.firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 5))
        tabs.buttons["AnyRouter"].tap()
        let info = app.buttons["model-info.anyrouter/openai/gpt-5"]
        XCTAssertTrue(info.waitForExistence(timeout: 5))
        info.tap()
        XCTAssertTrue(app.descendants(matching: .any)["model-detail"].waitForExistence(timeout: 5))
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

    func testFreeOnlyFilterLeavesOnlyFreeRows() {
        let app = launch()
        XCTAssertTrue(app.buttons["Model"].waitForExistence(timeout: 15))
        app.buttons["Model"].tap()
        let tabs = app.segmentedControls.firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 5))
        tabs.buttons["AnyRouter"].tap()
        XCTAssertTrue(app.buttons["model-filter"].waitForExistence(timeout: 5))
        app.buttons["model-filter"].tap()
        let free = app.switches["filter-free-only"]
        XCTAssertTrue(free.waitForExistence(timeout: 5))
        free.tap()
        app.buttons["Done"].tap()

        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'model-row.'"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(rows.count, 0)
        for index in 0..<rows.count {
            XCTAssertTrue(rows.element(boundBy: index).label.contains("Free"), "row \(index) is not free")
        }
    }
}
