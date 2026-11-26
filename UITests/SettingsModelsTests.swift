import XCTest

/// Settings > Local Models: the Not available list with its reasons, and the Delete All Models confirmation. Uses demo data.
@MainActor
final class SettingsModelsTests: XCTestCase {
    private func button(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func openLocalModels() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ARDemoData", "YES"]
        app.launch()
        app.revealSidebar(whenVisible: button(app, "Settings"))
        button(app, "Settings").tap()
        let row = button(app, "Local Models")
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        XCTAssertTrue(app.navigationBars["Local Models"].waitForExistence(timeout: 10))
        return app
    }

    private func scrollUntilHittable(_ element: XCUIElement, in app: XCUIApplication) {
        var tries = 0
        while !element.isHittable && tries < 8 {
            app.swipeUp()
            tries += 1
        }
        XCTAssertTrue(element.isHittable)
    }

    func testNotAvailableListsTooBigModelsWithTheReason() {
        let app = openLocalModels()
        let link = app.buttons["local.unavailable"]
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        scrollUntilHittable(link, in: app)
        XCTAssertTrue(link.label.contains("Not available on this"), "the row names the device")
        link.tap()
        XCTAssertTrue(app.navigationBars["Not Available"].waitForExistence(timeout: 10))
        let reason = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Needs about'")).firstMatch
        XCTAssertTrue(reason.waitForExistence(timeout: 5), "each row says how much memory it needs")
    }

    func testStarAndHideACloudModel() {
        let app = XCUIApplication()
        app.launchArguments = ["-ARDemoData", "YES"]
        app.launch()
        app.revealSidebar(whenVisible: button(app, "Settings"))
        button(app, "Settings").tap()
        let row = button(app, "AnyRouter Models")
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        let model = app.buttons["model-row.anyrouter/openai/gpt-5"]
        XCTAssertTrue(model.waitForExistence(timeout: 10))
        model.swipeRight()
        app.buttons["Star"].tap()
        XCTAssertTrue(app.staticTexts["Starred"].waitForExistence(timeout: 5), "a starred model gets its own section")
        let starred = app.buttons["model-row.anyrouter/openai/gpt-5"]
        starred.swipeLeft()
        app.buttons["Hide"].tap()
        XCTAssertTrue(app.buttons["anyrouter.hidden"].waitForExistence(timeout: 5), "a hidden model leaves a way back")
    }

    func testDeleteAllModelsAsksFirst() {
        let app = openLocalModels()
        let deleteAll = app.buttons["local.deleteAll"]
        XCTAssertTrue(deleteAll.waitForExistence(timeout: 10))
        scrollUntilHittable(deleteAll, in: app)
        deleteAll.tap()
        XCTAssertTrue(app.staticTexts["Delete all models?"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Cancel"].exists)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Local Models"].waitForExistence(timeout: 5), "cancel keeps the screen and the models")
    }
}
