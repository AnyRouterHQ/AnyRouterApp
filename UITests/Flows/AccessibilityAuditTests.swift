import XCTest

/// Walks the main screens and runs Apple's accessibility audit on each, in light and dark: hit regions (44pt),
/// contrast, clipped text and Dynamic Type. Every issue is listed in the failure, grouped by screen, so the
/// owning lane can fix it. Do not skip an issue here without a TODO that names the lane that owns the file.
@MainActor
final class AccessibilityAuditTests: XCTestCase {
    private let auditTypes: XCUIAccessibilityAuditType = [.hitRegion, .contrast, .textClipped, .dynamicType]
    private let appearances = ["light", "dark"]

    private func audit(_ app: XCUIApplication, _ screen: String, _ appearance: String) {
        var found: [String] = []
        do {
            try app.performAccessibilityAudit(for: auditTypes) { issue in
                let id = issue.element?.identifier ?? ""
                let label = issue.element?.label ?? ""
                found.append("\(issue.auditType.rawValue) | \(issue.compactDescription) | id=\(id) label=\(label)")
                return true
            }
        } catch {
            XCTFail("\(screen) (\(appearance)): the audit itself failed: \(error)")
        }
        guard !found.isEmpty else { return }
        let report = found.joined(separator: "\n")
        let attachment = XCTAttachment(string: report)
        attachment.name = "audit-\(screen)-\(appearance)"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTFail("\(screen) (\(appearance)): \(found.count) accessibility issue(s)\n\(report)")
    }

    private func button(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
    }

    private func eachAppearance(_ extra: [String] = [], _ body: (XCUIApplication, String) -> Void) {
        for appearance in appearances {
            let app = XCUIApplication.launchedOnDemoData(appearance: appearance, extra: extra)
            body(app, appearance)
            app.terminate()
        }
    }

    func testHome() {
        eachAppearance { app, appearance in
            XCTAssertTrue(app.element(UITestIDs.homeSubtitle).waitForExistence(timeout: 15))
            audit(app, "home", appearance)
        }
    }

    func testChatWithAMessage() {
        eachAppearance { app, appearance in
            app.revealSidebar(whenVisible: app.staticTexts["Explain Swift actors"])
            app.staticTexts["Explain Swift actors"].tap()
            XCTAssertTrue(app.staticTexts["Key points:"].waitForExistence(timeout: 10))
            audit(app, "chat", appearance)
        }
    }

    func testDrawer() {
        eachAppearance { app, appearance in
            app.revealSidebar(whenVisible: app.element(UITestIDs.sidebarHeader))
            audit(app, "drawer", appearance)
        }
    }

    func testSettingsAndTheme() {
        eachAppearance { app, appearance in
            app.revealSidebar(whenVisible: button(app, containing: "Settings"))
            button(app, containing: "Settings").tap()
            XCTAssertTrue(app.staticTexts["Account"].waitForExistence(timeout: 10))
            audit(app, "settings", appearance)
            let theme = app.buttons["Theme"]
            XCTAssertTrue(theme.waitForExistence(timeout: 5))
            theme.tap()
            XCTAssertTrue(app.buttons["Dark"].waitForExistence(timeout: 5))
            audit(app, "settings-theme", appearance)
        }
    }

    func testModelPicker() {
        eachAppearance { app, appearance in
            XCTAssertTrue(app.buttons["Model"].waitForExistence(timeout: 15))
            app.buttons["Model"].tap()
            let tabs = app.segmentedControls.firstMatch
            XCTAssertTrue(tabs.waitForExistence(timeout: 5))
            audit(app, "model-picker-local", appearance)
            tabs.buttons["AnyRouter"].tap()
            XCTAssertTrue(app.staticTexts["Top picks"].waitForExistence(timeout: 5))
            audit(app, "model-picker-anyrouter", appearance)
        }
    }

    func testHub() {
        eachAppearance { app, appearance in
            app.revealSidebar(whenVisible: button(app, containing: "Settings"))
            button(app, containing: "Settings").tap()
            let manage = button(app, containing: "Manage models")
            var swipes = 0
            while !manage.isHittable && swipes < 8 {
                app.swipeUp()
                swipes += 1
            }
            XCTAssertTrue(manage.isHittable, "Manage models is reachable in Settings")
            manage.tap()
            XCTAssertTrue(app.navigationBars["Manage models"].waitForExistence(timeout: 10))
            audit(app, "hub", appearance)
        }
    }
}
