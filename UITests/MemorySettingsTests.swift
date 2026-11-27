import XCTest

/// Settings > Memory: add an item, edit it, delete it. Demo data has no memories, so the page starts empty.
@MainActor
final class MemorySettingsTests: XCTestCase {
    private func button(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func openMemory() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ARDemoData", "YES"]
        app.launch()
        app.revealSidebar(whenVisible: button(app, "Settings"))
        button(app, "Settings").tap()
        let row = button(app, "Memory")
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        var tries = 0
        while !row.isHittable && tries < 8 {
            app.swipeUp()
            tries += 1
        }
        row.tap()
        XCTAssertTrue(app.navigationBars["Memory"].waitForExistence(timeout: 10))
        return app
    }

    private func type(_ text: String, in app: XCUIApplication, replacing old: String = "") {
        let field = app.alerts.textFields["settings.memory.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        if !old.isEmpty { field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count)) }
        field.typeText(text)
        app.alerts.buttons["Save"].tap()
    }

    func testAddEditAndDeleteAMemory() {
        let app = openMemory()
        XCTAssertTrue(app.staticTexts["No memories yet"].waitForExistence(timeout: 5), "an empty page says so")
        XCTAssertFalse(app.buttons["settings.memory.deleteAll"].isEnabled, "nothing to delete yet")

        app.buttons["settings.memory.add"].tap()
        app.buttons["Note"].tap()
        type("Buy oat milk", in: app)
        let added = button(app, "Buy oat milk")
        XCTAssertTrue(added.waitForExistence(timeout: 5), "the new item shows in its group")
        XCTAssertTrue(app.staticTexts["Pinned notes"].exists, "a note goes under Pinned notes")
        XCTAssertFalse(app.staticTexts["No memories yet"].exists)

        added.tap()
        type("Buy oat milk and tea", in: app, replacing: "Buy oat milk")
        XCTAssertTrue(button(app, "Buy oat milk and tea").waitForExistence(timeout: 5), "the edit is saved")

        button(app, "Buy oat milk and tea").swipeLeft()
        app.buttons["Delete"].tap()
        XCTAssertTrue(app.staticTexts["No memories yet"].waitForExistence(timeout: 5), "deleting the last item brings the empty page back")
    }

    func testAnEmptyItemIsRefusedWithAReason() {
        let app = openMemory()
        app.buttons["settings.memory.add"].tap()
        app.buttons["Fact"].tap()
        XCTAssertTrue(app.alerts.buttons["Save"].waitForExistence(timeout: 5))
        app.alerts.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Write something to remember."].waitForExistence(timeout: 5))
    }
}
