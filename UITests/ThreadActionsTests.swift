import XCTest

/// The rest of a chat row's long-press menu in the sidebar (ThreadMenuTests covers Archive): Pin turns into Unpin, Rename
/// changes the name the sidebar shows, and Delete asks first and then removes the chat. Demo data.
@MainActor
final class ThreadActionsTests: XCTestCase {
    private let title = "Dinner with chickpeas"

    private func launchAndPress() -> XCUIApplication {
        let app = XCUIApplication.launchedOnDemoData()
        pressRow(app)
        return app
    }

    private func pressRow(_ app: XCUIApplication) {
        let row = app.staticTexts[title]
        app.revealSidebar(whenVisible: row)
        XCTAssertTrue(row.waitForExistence(timeout: 10), "the demo chat is in the sidebar")
        row.press(forDuration: 1.2)
    }

    func testPinTurnsIntoUnpin() {
        let app = launchAndPress()
        let pin = app.element("thread.menu.pin")
        XCTAssertTrue(pin.waitForExistence(timeout: 5), "the menu offers Pin")
        XCTAssertEqual(pin.label, "Pin")
        pin.tap()
        XCTAssertTrue(pin.waitForNonExistence(timeout: 5), "the menu closes")
        pressRow(app)
        let unpin = app.element("thread.menu.pin")
        XCTAssertTrue(unpin.waitForExistence(timeout: 5), "the menu opens again")
        XCTAssertTrue(FlowWait.until(5) { unpin.label == "Unpin" }, "the pinned chat offers Unpin: \(unpin.label)")
    }

    func testRenameShowsTheNewNameInTheSidebar() {
        let app = launchAndPress()
        let rename = app.element("thread.menu.rename")
        XCTAssertTrue(rename.waitForExistence(timeout: 5), "the menu offers Rename")
        rename.tap()
        let alert = app.alerts["Rename chat"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "Rename opens an alert")
        let field = alert.textFields.firstMatch
        XCTAssertEqual(field.value as? String, title, "the alert starts with the current name")
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: title.count) + "Hummus supper")
        alert.buttons["Save"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Hummus supper"].waitForExistence(timeout: 10), "the sidebar lists the chat under its new name")
        XCTAssertFalse(app.staticTexts[title].exists, "the old name is gone")
    }

    func testDeleteAsksFirstAndThenRemovesTheChat() {
        let app = launchAndPress()
        let delete = app.element("thread.menu.delete")
        XCTAssertTrue(delete.waitForExistence(timeout: 5), "the menu offers Delete")
        delete.tap()
        XCTAssertTrue(app.labelled(containing: "Delete this chat?").waitForExistence(timeout: 5), "Delete asks first")
        app.buttons["Cancel"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 5), "Cancel keeps the chat")

        pressRow(app)
        app.element("thread.menu.delete").tap()
        XCTAssertTrue(app.labelled(containing: "Delete this chat?").waitForExistence(timeout: 5))
        app.buttons["Delete"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts[title].waitForNonExistence(timeout: 10), "the chat is gone from the sidebar")
    }
}
