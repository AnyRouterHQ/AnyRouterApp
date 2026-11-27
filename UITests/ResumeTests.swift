import XCTest

/// Coming back to the app keeps the open chat. "Start a new chat after" is Never by default; set to 1 minute it opens
/// a new chat after that long away, also on a cold launch (iOS ended the app in the background). The demo long thread
/// opens at launch, and `-ARDemoAwaySeconds` records the time away.
@MainActor
final class ResumeTests: XCTestCase {
    private func launch(awaySeconds: Int?, newChatAfter delay: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ARDemoData", "YES", "-ARDemoLongThread", "20"]
            + (awaySeconds.map { ["-ARDemoAwaySeconds", String($0)] } ?? [])
            + (delay.map { ["-settings.newChatDelay", $0] } ?? [])
        app.launch()
        return app
    }

    /// The operator's bug: switching to another app and back dropped the open chat for an empty one. More than the old
    /// one-minute default away, the same chat must still be open.
    func testSwitchingAppsAndComingBackKeepsTheOpenChat() {
        let app = launch(awaySeconds: nil)
        let chat = app.descendants(matching: .any)["chat.content"]
        XCTAssertTrue(chat.waitForExistence(timeout: 20), "the thread opens at launch")
        XCUIDevice.shared.press(.home)
        sleep(65)
        app.activate()
        XCTAssertTrue(chat.waitForExistence(timeout: 20), "65 seconds in another app: the same chat is open")
        XCTAssertFalse(app.buttons["home.greeting"].exists, "no new chat")
    }

    func testAColdLaunchAfterLongAwayReopensTheThreadByDefault() {
        let app = launch(awaySeconds: 3600)
        XCTAssertTrue(app.descendants(matching: .any)["chat.content"].waitForExistence(timeout: 20), "an hour away: same thread")
    }

    func testAColdLaunchAfterTheChosenDelayOpensANewChat() {
        let first = launch(awaySeconds: nil, newChatAfter: "oneMinute")
        XCTAssertTrue(first.descendants(matching: .any)["chat.content"].waitForExistence(timeout: 20), "the thread opens at launch")
        first.terminate()

        let app = launch(awaySeconds: 120, newChatAfter: "oneMinute")
        XCTAssertTrue(app.buttons["home.greeting"].waitForExistence(timeout: 20), "two minutes away with 1 minute chosen: a new chat")
        XCTAssertFalse(app.descendants(matching: .any)["chat.content"].exists, "the old thread must not reopen")
    }

    func testAColdLaunchBeforeTheChosenDelayKeepsTheThread() {
        let app = launch(awaySeconds: 10, newChatAfter: "oneMinute")
        XCTAssertTrue(app.descendants(matching: .any)["chat.content"].waitForExistence(timeout: 20), "ten seconds away: same thread")
    }
}
