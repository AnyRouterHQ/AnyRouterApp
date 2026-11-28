import XCTest

/// A photo app (Receipt sort) on demo data: the Simulator has no camera, so `-ARDemoDecisionPhoto YES` puts a drawn receipt
/// in the photo row. Run reads it and answers; Remove photo empties the row, and Add photo offers Photos and Files, with
/// Camera off because the Simulator has none.
@MainActor
final class PhotoDecisionTests: XCTestCase {
    private func openReceiptApp() -> XCUIApplication {
        let app = XCUIApplication.launchedOnDemoData(extra: ["-ARDemoDecisionPhoto", "YES"])
        let row = app.buttons["sidebar-apps"]
        app.revealSidebar(whenVisible: row)
        row.tap()
        let tile = app.buttons["apps-tile-receipt-sort"]
        XCTAssertTrue(tile.waitForExistence(timeout: 10), "Receipt sort is a tile on the Apps list")
        tile.tap()
        XCTAssertTrue(app.buttons["Remove photo"].waitForExistence(timeout: 15), "the demo photo is in the row")
        return app
    }

    func testRunReadsTheDemoPhotoAndAnswers() {
        let app = openReceiptApp()
        let run = app.buttons["decisions-run"]
        XCTAssertTrue(run.waitForExistence(timeout: 5))
        XCTAssertTrue(run.isEnabled, "a photo is enough to run")
        run.tap()
        XCTAssertTrue(app.element("decisions-result-line").waitForExistence(timeout: 15), "the photo gets an answer")
    }

    func testRemovingThePhotoEmptiesTheRowAndAddPhotoOffersItsSources() {
        let app = openReceiptApp()
        app.buttons["Remove photo"].tap()
        XCTAssertTrue(app.buttons["Remove photo"].waitForNonExistence(timeout: 5), "the row is empty again")
        XCTAssertFalse(app.buttons["decisions-run"].isEnabled, "Run needs a photo")

        let add = app.buttons["decisions-add-photo"]
        XCTAssertTrue(add.waitForExistence(timeout: 5), "the row offers Add photo")
        add.tap()
        XCTAssertTrue(app.buttons["Photos"].waitForExistence(timeout: 5), "the menu offers Photos")
        XCTAssertTrue(app.buttons["Files"].exists, "and Files")
        XCTAssertFalse(app.buttons["Camera"].isEnabled, "the Simulator has no camera")
    }
}
