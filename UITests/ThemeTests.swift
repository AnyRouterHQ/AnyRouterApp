import XCTest

/// Picks each theme in Settings while the sheet stays open and attaches a screenshot after each,
/// so a regression where the open sheet keeps the old theme is visible in the result bundle.
@MainActor
final class ThemeTests: XCTestCase {
    func testThemeChangesApplyInsideTheOpenSettingsSheet() {
        let app = XCUIApplication()
        app.launchArguments = ["-ARDemoData", "YES"]
        app.launch()

        func button(_ text: String) -> XCUIElement {
            app.buttons.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
        }
        if !button("Settings").waitForExistence(timeout: 2) {
            XCTAssertTrue(app.buttons["Menu"].waitForExistence(timeout: 10))
            app.buttons["Menu"].tap()
        }
        XCTAssertTrue(button("Settings").waitForExistence(timeout: 5))
        button("Settings").tap()
        let theme = app.buttons["Theme"]
        XCTAssertTrue(theme.waitForExistence(timeout: 5))
        theme.tap()

        for name in ["Dark", "Light", "System", "Light"] {
            let row = app.buttons[name]
            XCTAssertTrue(row.waitForExistence(timeout: 5), "\(name) row")
            row.tap()
            sleep(1)
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.name = "theme-\(name.lowercased())"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}
