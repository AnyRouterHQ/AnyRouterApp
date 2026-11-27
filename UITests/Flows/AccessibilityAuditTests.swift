import XCTest

/// Walks the main screens and runs Apple's accessibility audit on each, in light and dark: hit regions (44pt),
/// contrast, clipped text and Dynamic Type. Every issue is listed in the failure, grouped by screen, so the
/// owning lane can fix it. Do not skip an issue here without a TODO that names the lane that owns the file.
@MainActor
final class AccessibilityAuditTests: XCTestCase {
    private let auditTypes: XCUIAccessibilityAuditType = [.hitRegion, .contrast, .textClipped, .dynamicType]
    private let appearances = ["light", "dark"]

    /// Labels of the views in the iPhone drawer while it is CLOSED. The drawer then sits under the chat at opacity 0 and
    /// still shows up in XCUITest's tree (a run found the gear there), so the audit reports its contrast and clipping on
    /// Home. Those are the drawer's findings, audited in `testDrawer` with the drawer open; they are left out here.
    private func closedDrawerLabels(_ app: XCUIApplication) -> Set<String> {
        let menu = app.buttons["Menu"]
        guard menu.exists, menu.frame.minX < app.windows.firstMatch.frame.width / 2 else { return [] }
        let list = app.collectionViews.firstMatch
        guard list.exists, list.frame.minX == 0, list.frame.width < 345 else { return [] }
        var labels = Set<String>()
        for kind in [XCUIElement.ElementType.staticText, .button] {
            for element in list.descendants(matching: kind).allElementsBoundByIndex { labels.insert(element.label) }
        }
        for id in ["sidebar.header", "sidebar.settings", "sidebar.compose"] {
            let element = app.descendants(matching: .any)[id]
            if element.exists { labels.insert(element.label) }
        }
        labels.remove("")
        return labels
    }

    /// One audit pass: the issues as "type | description | id | label" lines.
    private func issues(_ app: XCUIApplication, skipping drawer: Set<String> = []) -> [String]? {
        var found: [String] = []
        do {
            try app.performAccessibilityAudit(for: auditTypes) { issue in
                let id = issue.element?.identifier ?? ""
                let label = (issue.element?.label ?? "").replacingOccurrences(of: "\n", with: " ")
                if !drawer.isEmpty, drawer.contains(label) || id.hasPrefix("sidebar") { return true }
                found.append("\(issue.auditType.rawValue) | \(issue.compactDescription) | id=\(id) label=\(label)")
                return true
            }
        } catch {
            return nil
        }
        return found
    }

    /// Audits twice, a second apart, after the screen has settled. Only an issue seen in both passes is reported:
    /// one that shows in a single pass came from a screen still animating (drawer, sheet, tab switch).
    private func audit(_ app: XCUIApplication, _ screen: String, _ appearance: String) {
        sleep(1)
        let drawer = closedDrawerLabels(app)
        guard let first = issues(app, skipping: drawer) else {
            XCTFail("\(screen) (\(appearance)): the audit itself failed")
            return
        }
        sleep(1)
        guard let second = issues(app, skipping: drawer) else {
            XCTFail("\(screen) (\(appearance)): the audit itself failed")
            return
        }
        let stable = first.filter(second.contains)
        let transient = Set(first).symmetricDifference(Set(second)).count
        let note = "\(stable.count) stable issue(s), \(transient) seen in only one pass (animation)"
            + (drawer.isEmpty ? "" : ", \(drawer.count) closed-drawer labels left out")
        let attachment = XCTAttachment(string: note + "\n" + stable.joined(separator: "\n"))
        attachment.name = "audit-\(screen)-\(appearance)"
        attachment.lifetime = .keepAlways
        add(attachment)
        guard !stable.isEmpty else { return }
        XCTFail("\(screen) (\(appearance)): \(note)\n\(stable.joined(separator: "\n"))")
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
            // The starter cards above the composer are part of Home: wait for them so the audit covers them.
            XCTAssertTrue(app.descendants(matching: .any)["composer.suggestions"].waitForExistence(timeout: 10))
            audit(app, "home", appearance)
        }
        // A copy waiting: the one-line chips (the copy's own chip and its quick actions) take the cards' place.
        UIPasteboard.general.string = "Can you send me the revised budget by Friday?"
        eachAppearance(["-ARDemoClipboard", "YES"]) { app, appearance in
            XCTAssertTrue(app.descendants(matching: .any)["composer.suggestion.clipboard"].waitForExistence(timeout: 15))
            audit(app, "home-clipboard", appearance)
        }
    }

    func testChatWithAMessage() {
        eachAppearance { app, appearance in
            app.revealSidebar(whenVisible: app.staticTexts["Explain Swift actors"])
            app.staticTexts["Explain Swift actors"].tap()
            XCTAssertTrue(app.replyText("Key points:").waitForExistence(timeout: 10))
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
            XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
            audit(app, "settings", appearance)
            let theme = app.buttons["Theme"]
            var swipes = 0
            while !theme.isHittable && swipes < 8 { app.swipeUp(); swipes += 1 }
            XCTAssertTrue(theme.isHittable, "Theme is reachable in Settings")
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
            XCTAssertTrue(app.buttons["model-row.anyrouter/anthropic/claude-sonnet-4-6"].waitForExistence(timeout: 5))
            audit(app, "model-picker-anyrouter", appearance)
        }
    }

    func testHub() {
        eachAppearance { app, appearance in
            app.revealSidebar(whenVisible: button(app, containing: "Settings"))
            button(app, containing: "Settings").tap()
            let manage = button(app, containing: "Local Models")
            var swipes = 0
            while !manage.isHittable && swipes < 8 {
                app.swipeUp()
                swipes += 1
            }
            XCTAssertTrue(manage.isHittable, "Local Models is reachable in Settings")
            manage.tap()
            XCTAssertTrue(app.navigationBars["Local Models"].waitForExistence(timeout: 10))
            audit(app, "hub", appearance)
        }
    }
}
