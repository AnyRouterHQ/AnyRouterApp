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

    func testASwipeOnARowPushesTheModelDetail() {
        let app = launch()
        XCTAssertTrue(app.buttons["Model"].waitForExistence(timeout: 15))
        app.buttons["Model"].tap()
        let tabs = app.segmentedControls.firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 5))
        tabs.buttons["AnyRouter"].tap()
        let row = app.buttons["model-row.anyrouter/openai/gpt-5"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["model-info.anyrouter/openai/gpt-5"].exists, "one trailing accessory: no ⓘ beside the checkmark")
        row.swipeLeft()
        let info = app.buttons["Details"].firstMatch
        XCTAssertTrue(info.waitForExistence(timeout: 5), "a swipe shows Details")
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

    func testNotAvailableListsWhatCannotBeUsedWithReasons() {
        let app = launch()
        XCTAssertTrue(app.buttons["Model"].waitForExistence(timeout: 15))
        app.buttons["Model"].tap()
        let tabs = app.segmentedControls.firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 5))
        tabs.buttons["AnyRouter"].tap()
        XCTAssertFalse(app.buttons["model-row.anyrouter/x-ai/grok-4"].exists, "a model that needs a key is not in the list")
        app.buttons["model-picker.not-available"].tap()
        let key = app.buttons["unavailable-row.anyrouter/x-ai/grok-4"]
        XCTAssertTrue(key.waitForExistence(timeout: 5))
        XCTAssertTrue(key.label.contains("Add your own key (BYOK) for xAI"), "reason: \(key.label)")
        key.tap()
        XCTAssertTrue(app.alerts["Needs your provider key"].waitForExistence(timeout: 5), "tapping offers to add the key")
    }

    /// The Local tab's Not available list only asks for a download: the fit estimate is never a reason there.
    func testLocalNotAvailableOnlyAsksForADownload() {
        let app = launch()
        XCTAssertTrue(app.buttons["Model"].waitForExistence(timeout: 15))
        app.buttons["Model"].tap()
        let tabs = app.segmentedControls.firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 5))
        tabs.buttons["Local"].tap()
        let notAvailable = app.buttons["model-picker.not-available"]
        XCTAssertTrue(notAvailable.waitForExistence(timeout: 5))
        notAvailable.tap()
        let download = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Download first")).firstMatch
        XCTAssertTrue(download.waitForExistence(timeout: 5), "a model not on the device says Download first")
        let tooBig = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Qwen3 14B")).firstMatch
        XCTAssertTrue(tooBig.exists, "a model the estimate doubts is listed")
        XCTAssertTrue(tooBig.label.contains("Download first"), "and only needs its download: \(tooBig.label)")
    }

    /// An installed model the estimate calls too big stays in the Local tab and can be picked (-ARDemoTooBigInstalled).
    func testAnInstalledModelTheEstimateDoubtsIsPickable() {
        let app = XCUIApplication()
        app.launchArguments = ["-ARDemoData", "YES", "-ARDemoTooBigInstalled", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["Model"].waitForExistence(timeout: 15))
        app.buttons["Model"].tap()
        let tabs = app.segmentedControls.firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 5))
        tabs.buttons["Local"].tap()
        let row = app.buttons["model-row.gguf/bartowski/Meta-Llama-3.1-8B-Instruct-GGUF/Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "it is listed with the downloaded models")
        XCTAssertTrue(row.label.contains("May not load on this"), "with a quiet line: \(row.label)")
        row.tap()
        XCTAssertTrue(app.buttons["Model"].waitForExistence(timeout: 5))
        let title = app.buttons["Model"].value as? String ?? ""
        XCTAssertTrue(title.contains("Llama 3.1"), "picking it makes it the chat's model: \(title)")
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
        // The switch element spans the row; a tap at its center lands on the label and does not flip it (the free filter
        // was never on in screenshots 46052222870 and 46075429647).
        free.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        XCTAssertEqual(free.value as? String, "1", "Free only is on")
        app.buttons["Done"].tap()

        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "model-row."))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(rows.count, 0)
        for index in 0..<rows.count {
            XCTAssertTrue(rows.element(boundBy: index).label.contains("Free"), "row \(index) is not free")
        }
    }
}
