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
        app.revealSidebar(whenVisible: button("Settings"))
        button("Settings").tap()
        // The list is lazy and Theme sits below the first screen of rows: scroll until it can be tapped.
        let theme = app.buttons["Theme"]
        var tries = 0
        while !(theme.exists && theme.isHittable) && tries < 8 {
            app.swipeUp()
            tries += 1
        }
        XCTAssertTrue(theme.isHittable, "Theme row")
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
