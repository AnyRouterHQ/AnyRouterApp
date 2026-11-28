import XCTest

/// A copied text offers quick actions; one tap reads the copy, sends, and the sent message carries the clipboard badge.
/// `-ARDemoClipboard YES` makes the demo app offer the copy; the runner puts the text on the system pasteboard.
@MainActor
final class ClipboardQuickSendUITests: XCTestCase {
    func testAQuickActionSendsTheCopyWithABadge() {
        UIPasteboard.general.string = "Hi team, the budget review moved to Friday. Please send the revised numbers by Thursday noon."
        let app = XCUIApplication()
        app.launchArguments = ["-ARDemoData", "YES", "-ARDemoClipboard", "YES"]
        app.launch()

        // The first card, in view on every device: the cards act on the copy.
        let fix = app.descendants(matching: .any)["composer.suggestion.preset.fix-english"]
        XCTAssertTrue(fix.waitForExistence(timeout: 15), "Fix my English is a quick action for copied text")
        fix.tap()

        // Reading the pasteboard in code asks once per tap unless the person allowed it in Settings.
        let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Allow Paste"]
        if allow.waitForExistence(timeout: 3) { allow.tap() }

        XCTAssertTrue(app.descendants(matching: .any)["message.clipboard-badge"].waitForExistence(timeout: 10),
                      "the sent message says it came from the clipboard")
        XCTAssertFalse(fix.exists, "the offer is used up once the chat has a message")
    }
}
