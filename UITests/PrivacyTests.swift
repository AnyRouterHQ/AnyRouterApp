import XCTest

/// Settings > Privacy > Delete All Conversations: reachable, asks first, then deletes. Uses demo data (which has threads).
@MainActor
final class PrivacyTests: XCTestCase {
    private func button(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    func testDeleteAllConversationsIsInPrivacyAndDeletesAfterConfirmation() {
        let app = XCUIApplication()
        app.launchArguments = ["-ARDemoData", "YES"]
        app.launch()
        app.revealSidebar(whenVisible: button(app, "Settings"))
        button(app, "Settings").tap()
        XCTAssertFalse(button(app, "Delete conversation history").exists, "it moved out of the main list")
        let privacy = app.buttons["Privacy"]
        var tries = 0
        while !(privacy.exists && privacy.isHittable) && tries < 8 {
            app.swipeUp()
            tries += 1
        }
        privacy.tap()
        let deleteAll = app.buttons["privacy.deleteAll"]
        XCTAssertTrue(deleteAll.waitForExistence(timeout: 10))
        XCTAssertTrue(deleteAll.isEnabled, "the demo has conversations")
        deleteAll.tap()
        XCTAssertTrue(app.staticTexts["Delete all conversations?"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(deleteAll.isEnabled, "cancel keeps them")
        deleteAll.tap()
        app.buttons["Delete All Conversations"].firstMatch.tap()
        let disabled = NSPredicate(format: "isEnabled == false")
        expectation(for: disabled, evaluatedWith: deleteAll)
        waitForExpectations(timeout: 10)
    }
}
