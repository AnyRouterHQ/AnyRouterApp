import XCTest

/// The Presets sheet from the composer's + menu: search narrows it, a preset with choices (Reply to this) asks for its message
/// before it sends, and a plain preset (Fix my English) fills the composer. Nothing is sent.
@MainActor
final class PresetSheetTests: XCTestCase {
    private func openSheet(_ app: XCUIApplication) {
        let plus = app.buttons["Add"]
        XCTAssertTrue(plus.waitForExistence(timeout: 15))
        plus.tap()
        let presets = app.buttons["composer.presets"]
        XCTAssertTrue(presets.waitForExistence(timeout: 5), "the + menu has Presets")
        presets.tap()
        XCTAssertTrue(app.navigationBars["Presets"].waitForExistence(timeout: 10), "the Presets sheet opened")
    }

    /// A preset row of the sheet's list. The chat behind it has chips with the same words, but not inside a collection view.
    private func sheetRow(_ app: XCUIApplication, _ title: String) -> XCUIElement {
        app.collectionViews.buttons.matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
    }

    func testSearchNarrowsTheListAndAPresetWithChoicesAsksForItsMessage() {
        let app = XCUIApplication.launchedOnDemoData()
        openSheet(app)
        let search = app.searchFields["Search presets"]
        XCTAssertTrue(search.waitForExistence(timeout: 5), "the sheet is searchable")
        search.tap()
        search.typeText("qqqzzz")
        XCTAssertTrue(app.labelled(containing: "No presets match").waitForExistence(timeout: 5), "a search with no match says so")
        search.buttons["Clear text"].tap()
        search.typeText("Reply to this")

        let reply = sheetRow(app, "Reply to this")
        XCTAssertTrue(reply.waitForExistence(timeout: 5), "the preset is listed")
        reply.tap()
        let message = app.element("preset-options.message")
        XCTAssertTrue(message.waitForExistence(timeout: 10), "a preset with choices asks for the message")
        XCTAssertFalse(app.buttons["preset-options.confirm"].isEnabled, "Send waits for a message")
        message.tap()
        message.typeText("Thanks for the update")
        XCTAssertTrue(app.buttons["preset-options.confirm"].isEnabled, "a message enables Send")
        app.navigationBars["Reply to this"].buttons["Cancel"].tap()
        XCTAssertTrue(message.waitForNonExistence(timeout: 5), "Cancel closes the choices")
    }

    func testAPlainPresetFillsTheComposer() {
        let app = XCUIApplication.launchedOnDemoData()
        openSheet(app)
        let row = sheetRow(app, "Fix my English")
        XCTAssertTrue(row.waitForExistence(timeout: 10), "Fix my English is listed")
        row.tap()
        XCTAssertTrue(app.navigationBars["Presets"].waitForNonExistence(timeout: 5), "picking a preset closes the sheet")
        let input = app.element(UITestIDs.composerInput)
        XCTAssertTrue(FlowWait.until(5) { !(input.value as? String ?? "").isEmpty && (input.value as? String) != "Ask anything" },
                      "the composer now holds the preset's words: \(String(describing: input.value))")
    }
}
