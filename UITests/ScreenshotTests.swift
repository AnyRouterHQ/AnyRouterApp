import XCTest

/// Captures every main screen from demo data (launch argument `-ARDemoData YES`), light and dark.
/// PNGs are attached to the result bundle and, when SCREENSHOT_DIR is set (via TEST_RUNNER_SCREENSHOT_DIR),
/// written to that folder as `<appearance>-<screen>.png`.
@MainActor
final class ScreenshotTests: XCTestCase {
    private enum Appearance: String, CaseIterable { case light, dark }

    private func forEachAppearance(extra: [String] = [], _ body: (XCUIApplication, Appearance) -> Void) {
        for appearance in Appearance.allCases {
            let app = XCUIApplication()
            app.launchArguments = ["-ARDemoData", "YES", "-ARAppearance", appearance.rawValue] + extra
            app.launch()
            body(app, appearance)
            app.terminate()
        }
    }

    private func capture(_ name: String, _ appearance: Appearance) {
        sleep(1)
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "\(appearance.rawValue)-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
        guard let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"], !dir.isEmpty else { return }
        let url = URL(fileURLWithPath: dir).appendingPathComponent("\(appearance.rawValue)-\(name).png")
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try screenshot.pngRepresentation.write(to: url)
        } catch {
            XCTFail("Could not write \(url.lastPathComponent): \(error)")
        }
    }

    private func button(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// iPhone: the sidebar is a drawer behind the menu button. iPad: a column, open in landscape only.
    private func showSidebar(_ app: XCUIApplication) {
        app.revealSidebar(whenVisible: button(app, containing: "Settings"))
    }

    private func open(_ app: XCUIApplication, footer title: String) {
        showSidebar(app)
        button(app, containing: title).tap()
    }

    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        var tries = 0
        while !element.isHittable && tries < 8 {
            app.swipeUp()
            tries += 1
        }
        XCTAssertTrue(element.isHittable)
    }

    func testOnboarding() {
        forEachAppearance(extra: ["-ARDemoOnboarding", "YES"]) { app, appearance in
            XCTAssertTrue(app.staticTexts["Choose how to chat"].waitForExistence(timeout: 15))
            capture("onboarding", appearance)
        }
    }

    func testEmptyChat() {
        forEachAppearance { app, appearance in
            XCTAssertTrue(app.staticTexts["How can I help?"].waitForExistence(timeout: 15))
            capture("empty-chat", appearance)
        }
    }

    func testThreadList() {
        forEachAppearance { app, appearance in
            showSidebar(app)
            XCTAssertTrue(app.staticTexts["Explain Swift actors"].waitForExistence(timeout: 5))
            capture("thread-list", appearance)
        }
    }

    func testChatWithMarkdown() {
        forEachAppearance { app, appearance in
            showSidebar(app)
            app.staticTexts["Explain Swift actors"].tap()
            XCTAssertTrue(app.staticTexts["Key points:"].waitForExistence(timeout: 10))
            capture("chat-markdown", appearance)
        }
    }

    func testResponseDetailsAndSwitchNote() {
        forEachAppearance { app, appearance in
            showSidebar(app)
            app.staticTexts["Switch models in a chat"].tap()
            XCTAssertTrue(app.staticTexts["switch-note"].waitForExistence(timeout: 10))
            capture("response-footer", appearance)
            let details = app.buttons["response-details"].firstMatch
            XCTAssertTrue(details.waitForExistence(timeout: 5))
            details.tap()
            XCTAssertTrue(app.staticTexts["req_demo01"].waitForExistence(timeout: 5)
                || app.staticTexts["req_demo02"].waitForExistence(timeout: 5))
            capture("response-details", appearance)
        }
    }

    func testModelPickerFilters() {
        forEachAppearance { app, appearance in
            XCTAssertTrue(app.buttons["Model"].waitForExistence(timeout: 15))
            app.buttons["Model"].tap()
            let tabs = app.segmentedControls.firstMatch
            XCTAssertTrue(tabs.waitForExistence(timeout: 5))
            tabs.buttons["AnyRouter"].tap()
            XCTAssertTrue(app.buttons["model-filter"].waitForExistence(timeout: 5))
            app.buttons["model-filter"].tap()
            XCTAssertTrue(app.switches["filter-free-only"].waitForExistence(timeout: 5))
            capture("model-filters", appearance)
            app.switches["filter-free-only"].tap()
            app.buttons["Done"].tap()
            capture("model-picker-free", appearance)
        }
    }

    func testComposerWithText() {
        forEachAppearance { app, appearance in
            XCTAssertTrue(app.staticTexts["How can I help?"].waitForExistence(timeout: 15))
            let field = app.textViews.firstMatch.exists ? app.textViews.firstMatch : app.textFields.firstMatch
            field.tap()
            field.typeText("Write a haiku about routers")
            capture("composer-text", appearance)
        }
    }

    func testModelPicker() {
        forEachAppearance { app, appearance in
            XCTAssertTrue(app.buttons["Model"].waitForExistence(timeout: 15))
            app.buttons["Model"].tap()
            let tabs = app.segmentedControls.firstMatch
            XCTAssertTrue(tabs.waitForExistence(timeout: 5))
            capture("model-picker-local", appearance)
            tabs.buttons["AnyRouter"].tap()
            XCTAssertTrue(app.staticTexts["Top picks"].waitForExistence(timeout: 5))
            capture("model-picker", appearance)
        }
    }

    func testHub() {
        forEachAppearance { app, appearance in
            // The sidebar has no hub entry any more: Settings > Models > Local Models.
            open(app, footer: "Settings")
            let manage = button(app, containing: "Local Models")
            XCTAssertTrue(manage.waitForExistence(timeout: 10))
            scrollTo(manage, in: app)
            manage.tap()
            XCTAssertTrue(app.navigationBars["Local Models"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.staticTexts["Storage"].waitForExistence(timeout: 10) || app.otherElements["local.storage"].exists)
            // Rows are list cells with a link, so match by label instead of a static text id.
            let qwen = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Qwen3 0.6B'")).firstMatch
            XCTAssertTrue(qwen.waitForExistence(timeout: 10))
            capture("hub", appearance)
        }
    }

    func testDecisions() {
        forEachAppearance { app, appearance in
            showSidebar(app)
            app.buttons["sidebar-decisions"].tap()
            XCTAssertTrue(app.navigationBars["Decisions"].waitForExistence(timeout: 10))
            capture("decisions", appearance)
        }
    }

    func testAttachmentChip() {
        forEachAppearance(extra: ["-ARDemoAttachFile", "YES"]) { app, appearance in
            XCTAssertTrue(app.descendants(matching: .any)["attachment-chip.notes.txt"].waitForExistence(timeout: 20))
            capture("attachment-chip", appearance)
        }
    }

    func testSettings() {
        forEachAppearance { app, appearance in
            open(app, footer: "Settings")
            XCTAssertTrue(app.staticTexts["Account"].waitForExistence(timeout: 10))
            capture("settings", appearance)
            app.swipeUp()
            app.swipeUp()
            capture("settings-more", appearance)
        }
    }

    func testSettingsAccountSignedOut() {
        forEachAppearance(extra: ["-ARDemoSignedOut", "YES"]) { app, appearance in
            open(app, footer: "Settings")
            XCTAssertTrue(app.buttons["Sign in with AnyRouter"].waitForExistence(timeout: 10))
            capture("settings-account", appearance)
        }
    }

    func testLicenses() {
        forEachAppearance { app, appearance in
            open(app, footer: "Settings")
            let licenses = app.buttons["Licenses"]
            XCTAssertTrue(licenses.waitForExistence(timeout: 10) || app.staticTexts["Account"].exists)
            scrollTo(licenses, in: app)
            licenses.tap()
            XCTAssertTrue(app.staticTexts["Licenses"].waitForExistence(timeout: 5))
            capture("licenses", appearance)
        }
    }
}
