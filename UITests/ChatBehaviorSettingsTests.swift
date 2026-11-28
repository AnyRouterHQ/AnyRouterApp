import XCTest

/// Settings > Chat Behavior: the keyboard switch flips, and the "Start a new chat after" picker takes another delay.
/// The Paste from Other Apps row leaves the app for iOS Settings, so it is only looked for.
@MainActor
final class ChatBehaviorSettingsTests: XCTestCase {
    func testTheKeyboardSwitchAndTheNewChatDelayChange() {
        let app = XCUIApplication.launchedOnDemoData()
        app.showSettingsPage("Chat Behavior")

        let keyboard = app.switches["settings-show-keyboard"]
        XCTAssertTrue(keyboard.waitForExistence(timeout: 10), "the keyboard switch is on the page")
        XCTAssertTrue(app.flipSwitch(keyboard), "the keyboard switch changed")

        let picker = app.buttons["settings-new-chat-after"]
        XCTAssertTrue(picker.exists, "the new chat picker is on the page")
        picker.tap()
        let choice = app.buttons["1 minute"].firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: 5), "the picker offers 1 minute")
        choice.tap()
        XCTAssertTrue(FlowWait.until(5) { app.words(of: picker).contains("1 minute") }, "the picker now says 1 minute: \(app.words(of: picker))")

        XCTAssertTrue(app.element("settings-paste-permission").exists, "the Paste from Other Apps row is there")
    }
}
