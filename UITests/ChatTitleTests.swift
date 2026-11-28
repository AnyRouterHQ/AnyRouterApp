import XCTest

/// Renaming a chat from its own "..." menu (demo data, the long thread opens at launch). The sidebar shows the new name.
@MainActor
final class ChatTitleTests: XCTestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ARDemoData", "YES", "-ARDemoLongThread", "20"]
        app.launch()
        return app
    }

    func testRenameFromTheChatMenuShowsInTheSidebar() {
        let app = launch()
        XCTAssertTrue(app.descendants(matching: .any)["chat.content"].waitForExistence(timeout: 20), "the thread opens at launch")
        app.buttons["chat.more"].tap()
        let rename = app.buttons["chat.rename"]
        XCTAssertTrue(rename.waitForExistence(timeout: 5), "the menu offers Rename")
        rename.tap()

        let alert = app.alerts["Rename chat"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "Rename opens an alert")
        let field = alert.textFields.firstMatch
        XCTAssertEqual(field.value as? String, "Long thread", "the alert starts with the current title")
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "Long thread".count) + "Weekend in Porto")
        // The alert's button carries its identifier twice in the tree (verify-ui 46091124302), so take the first.
        alert.buttons["Save"].firstMatch.tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 5), "Save closes the alert")

        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Weekend in Porto")).firstMatch
        app.revealSidebar(whenVisible: row)
        XCTAssertTrue(row.exists, "the sidebar lists the chat under its new name")
        let old = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Long thread")).firstMatch
        XCTAssertFalse(old.exists, "the old name is gone")
    }
}
