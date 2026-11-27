import XCTest

/// "Start a new chat after" (1 minute by default) on a cold launch: iOS ended the app in the background, the person
/// opens it again. The demo long thread opens at launch, and `-ARDemoAwaySeconds` records the time away.
@MainActor
final class ResumeTests: XCTestCase {
    private func launch(awaySeconds: Int?) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ARDemoData", "YES", "-ARDemoLongThread", "20"]
            + (awaySeconds.map { ["-ARDemoAwaySeconds", String($0)] } ?? [])
        app.launch()
        return app
    }

    func testAColdLaunchAfterTheDelayOpensANewChat() {
        let first = launch(awaySeconds: nil)
        XCTAssertTrue(first.descendants(matching: .any)["chat.content"].waitForExistence(timeout: 20), "the thread opens at launch")
        first.terminate()

        let app = launch(awaySeconds: 120)
        XCTAssertTrue(app.buttons["home.greeting"].waitForExistence(timeout: 20), "two minutes away: a new chat")
        XCTAssertFalse(app.descendants(matching: .any)["chat.content"].exists, "the old thread must not reopen")
    }

    func testAColdLaunchBeforeTheDelayKeepsTheThread() {
        let app = launch(awaySeconds: 10)
        XCTAssertTrue(app.descendants(matching: .any)["chat.content"].waitForExistence(timeout: 20), "ten seconds away: same thread")
    }
}
