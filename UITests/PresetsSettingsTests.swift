import XCTest

/// Settings > Presets: add a preset of your own (Save waits for a title and a prompt), see it listed, delete it.
@MainActor
final class PresetsSettingsTests: XCTestCase {
    func testAddAPresetAndDeleteIt() {
        let app = XCUIApplication.launchedOnDemoData()
        app.showSettingsPage("Presets")
        let add = app.buttons["Add preset"]
        XCTAssertTrue(add.waitForExistence(timeout: 10), "the page offers Add preset")
        add.tap()

        let sheet = app.navigationBars["New preset"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 10), "the editor opened")
        XCTAssertFalse(sheet.buttons["Save"].isEnabled, "Save needs a title and a prompt")
        let title = app.element("preset-editor.title")
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("Plain words")
        XCTAssertFalse(sheet.buttons["Save"].isEnabled, "a title alone is not enough")
        let prompt = app.element("preset-editor.prompt")
        prompt.tap()
        prompt.typeText("Say it in plain words")
        XCTAssertTrue(sheet.buttons["Save"].isEnabled, "a title and a prompt enable Save")
        sheet.buttons["Save"].tap()
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 5), "Save closes the editor")

        let saved = app.listRow("Plain words")
        XCTAssertTrue(saved.waitForExistence(timeout: 5), "the preset is listed under Your presets")
        saved.swipeLeft()
        app.buttons["Delete"].firstMatch.tap()
        XCTAssertTrue(saved.waitForNonExistence(timeout: 5), "deleting takes it out of the list")
    }
}
