import XCTest

/// Settings > Skills (unit K2): the three bundled skills, the empty "yours" list, and an import that refuses a link that
/// is not https before anything is fetched or saved.
@MainActor
final class SkillsSettingsTests: XCTestCase {
    private func button(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func openSkills() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ARDemoData", "YES"]
        app.launch()
        app.revealSidebar(whenVisible: button(app, "Settings"))
        button(app, "Settings").tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10), "Settings opened")
        let row = button(app, "Skills")
        var tries = 0
        while (!row.exists || !row.isHittable) && tries < 8 {
            app.swipeUp()
            tries += 1
        }
        XCTAssertTrue(row.isHittable, "the Skills row is reachable")
        row.tap()
        XCTAssertTrue(app.navigationBars["Skills"].waitForExistence(timeout: 10), "the Skills page opened")
        return app
    }

    func testBundledSkillsShowAndANonHttpsLinkIsRefused() {
        let app = openSkills()
        let bundled = app.descendants(matching: .any).matching(identifier: "settings.skills.bundled")
        XCTAssertTrue(bundled.firstMatch.waitForExistence(timeout: 5), "the built-in skills show")
        // Each row answers to its identifier on a few nested elements (verify-ui 46121182428 counted 9), so count the names.
        let names = Set(bundled.allElementsBoundByIndex.map(\.label).filter { !$0.isEmpty })
        XCTAssertEqual(names.count, 3, "three skills ship with the app: \(names)")
        XCTAssertTrue(app.descendants(matching: .any)["settings.skills.empty"].exists, "no skills of the user's own yet")

        let importButton = app.buttons["settings.skills.import"]
        var tries = 0
        while !importButton.isHittable && tries < 6 {
            app.swipeUp()
            tries += 1
        }
        importButton.tap()
        let field = app.alerts.textFields["settings.skills.link"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Import asks for a link")
        field.tap()
        field.typeText("http://example.com/SKILL.md")
        app.alerts.buttons["Import"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["settings.skills.error"].waitForExistence(timeout: 10), "a link that is not https is refused with a reason")
        XCTAssertFalse(app.descendants(matching: .any)["settings.skills.row"].exists, "nothing was saved")
    }
}
