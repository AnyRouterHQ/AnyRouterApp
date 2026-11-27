import XCTest

/// Extract from the composer's + menu, on demo data (no network, no model: the answer is canned).
@MainActor
final class ExtractTests: XCTestCase {
    private func launch(stage: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ARDemoData", "YES"] + (stage.map { ["-ARDemoExtract", $0] } ?? [])
        app.launch()
        return app
    }

    private func openFromPlusMenu(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["Add"].waitForExistence(timeout: 15))
        app.buttons["Add"].tap()
        let item = app.buttons["composer.extract"]
        XCTAssertTrue(item.waitForExistence(timeout: 5), "Extract fields is in the + menu")
        item.tap()
        XCTAssertTrue(app.navigationBars["Extract"].waitForExistence(timeout: 10))
    }

    func testExtractOpensEmptyAndNeedsADocument() {
        let app = launch()
        openFromPlusMenu(app)
        XCTAssertTrue(app.buttons["extract-source"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["extract-model"].exists)
        let run = app.buttons["extract-run"]
        XCTAssertTrue(run.waitForExistence(timeout: 5))
        XCTAssertFalse(run.isEnabled, "Extract needs a document")
    }

    func testTheAppsListOpensExtract() {
        let app = launch()
        let row = app.buttons["sidebar-apps"]
        app.revealSidebar(whenVisible: row)
        row.tap()
        XCTAssertTrue(app.navigationBars["Apps"].waitForExistence(timeout: 10))
        let tile = app.buttons["apps-extract"]
        XCTAssertTrue(tile.waitForExistence(timeout: 5), "Extract is a tile on the Apps list")
        tile.tap()
        XCTAssertTrue(app.navigationBars["Extract"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["extract-source"].waitForExistence(timeout: 5))
    }

    func testExtractFillsFieldsAndTappingOneSelectsItsSource() {
        let app = launch(stage: "document")
        openFromPlusMenu(app)
        XCTAssertTrue(app.staticTexts["TOTAL 80,000"].waitForExistence(timeout: 5), "the document text is shown")
        let run = app.buttons["extract-run"]
        XCTAssertTrue(run.isEnabled)
        run.tap()

        let total = app.buttons["extract-field-Total"]
        XCTAssertTrue(total.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Not found in the text"].exists, "a quote that is not in the text says so")
        XCTAssertFalse(total.isSelected)
        total.tap()
        XCTAssertTrue(total.isSelected, "the tapped field is the selected one")
    }
}
