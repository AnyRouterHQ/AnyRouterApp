import XCTest

/// Voice Mode's gate (the cover the voice button opens before a speech model is on the phone): it names the model and its
/// download, and Not now closes it. The download itself is VoiceDownloadTests. When a speech model is already usable the
/// voice button dictates at once and the test is skipped, as in ScreenshotTests.testVoiceModeGate.
@MainActor
final class VoiceGateTests: XCTestCase {
    func testTheGateNamesTheModelAndNotNowClosesIt() throws {
        let app = XCUIApplication.launchedOnDemoData()
        let voice = app.buttons["Voice input"]
        XCTAssertTrue(voice.waitForExistence(timeout: 15))
        voice.tap()
        guard app.element("voice-gate.title").waitForExistence(timeout: 5) else {
            throw XCTSkip("No speech model fits this simulator, so the voice button dictates at once")
        }
        XCTAssertTrue(app.element("voice-gate.model").exists, "the gate names the model")
        XCTAssertTrue(app.buttons["voice-gate.download"].exists, "and offers its download")
        let notNow = app.buttons["voice-gate.not-now"]
        XCTAssertTrue(notNow.exists, "and a way out")
        notNow.tap()
        XCTAssertTrue(app.element("voice-gate.title").waitForNonExistence(timeout: 5), "Not now closes the gate")
        XCTAssertTrue(app.element(UITestIDs.composerInput).isHittable, "the chat is back")
    }
}
