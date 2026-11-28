import XCTest

/// Settings > Shortcuts & Controls: the phrases Siri knows, then every way to reach the app from outside it.
/// Nothing here is tapped: the Siri tip and the Shortcuts link leave the app.
@MainActor
final class ShortcutsSettingsTests: XCTestCase {
    func testShortcutsListsTheSiriPhrasesAndEachWayToReachTheApp() {
        let app = XCUIApplication.launchedOnDemoData()
        app.showSettingsPage("Shortcuts & Controls")
        XCTAssertTrue(app.element("settings-shortcuts").waitForExistence(timeout: 10), "the page's list is there")
        XCTAssertTrue(app.labelled(containing: "Fix my English with AnyRouter").waitForExistence(timeout: 10), "a Siri phrase is listed")

        // The last way sits below the first screen; the list builds its rows as it scrolls.
        let last = app.labelled(containing: "Read text from a photo")
        app.scrollPage(under: app.navigationBars["Shortcuts & Controls"], until: last)
        XCTAssertTrue(last.exists, "the last way to reach the app is listed")
        XCTAssertTrue(app.labelled(containing: "How to add").exists, "each way says how to add it")
    }
}
