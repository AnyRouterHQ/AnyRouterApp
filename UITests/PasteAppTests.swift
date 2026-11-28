import XCTest

/// The Paste app on the Apps list: what the device finds in a paste shows as its own card (JSON, here), plain text shows
/// none, and the Recent button opens the list of earlier runs. Demo data; no decision model is called.
@MainActor
final class PasteAppTests: XCTestCase {
    private func openPaste() -> XCUIApplication {
        let app = XCUIApplication.launchedOnDemoData()
        let row = app.buttons["sidebar-apps"]
        app.revealSidebar(whenVisible: row)
        row.tap()
        let tile = app.buttons["apps-tile-paste"]
        XCTAssertTrue(tile.waitForExistence(timeout: 10), "Paste is a tile on the Apps list")
        tile.tap()
        XCTAssertTrue(app.navigationBars["Paste"].waitForExistence(timeout: 10), "the Paste app opened")
        return app
    }

    func testAPastedJSONShowsItsCardAndPlainTextShowsNone() {
        let app = openPaste()
        let json = app.buttons["decisions-sample-JSON"]
        XCTAssertTrue(json.waitForExistence(timeout: 5), "the app offers a JSON sample")
        json.tap()
        XCTAssertTrue(app.element("paste-card").waitForExistence(timeout: 5), "JSON gets a card of its own")

        let note = app.buttons["decisions-sample-Note"]
        note.tap()
        XCTAssertTrue(app.element("paste-card").waitForNonExistence(timeout: 5), "plain text has no card, a decision model reads it")
    }

    func testRecentOpensTheListOfEarlierRunsAndCloseReturns() {
        let app = openPaste()
        let recent = app.buttons["decisions-recent"]
        XCTAssertTrue(recent.waitForExistence(timeout: 5), "the bar has Recent")
        recent.tap()
        let sheet = app.navigationBars["Recent"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 10), "the Recent list opened")
        sheet.buttons["Close"].tap()
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 5), "Close returns to the app")
        XCTAssertTrue(app.navigationBars["Paste"].exists, "back on the Paste app")
    }
}
