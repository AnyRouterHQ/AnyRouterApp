import XCTest

/// Voice Mode's model download from the gate: it starts in the background, the cover closes, the chat stays usable, and the
/// progress is in Settings > Local Models > Voice with Cancel. Demo data: the download never reaches the network, it
/// stops part way. (The ring on the composer's voice button belongs to the composer and is not asserted here.)
@MainActor
final class VoiceDownloadTests: XCTestCase {
    private func button(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id]
    }

    /// Drags inside the page under `bar`: on iPad Settings is a form sheet, and a swipe at the app's center lands
    /// beside it, so nothing scrolled (verify-ui 46083174976 failed here on both iPads).
    private func scrollUntilHittable(_ element: XCUIElement, under bar: XCUIElement) {
        var tries = 0
        while !element.isHittable && tries < 8 {
            let start = bar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).withOffset(CGVector(dx: 0, dy: 450))
            start.press(forDuration: 0.01, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -300)))
            tries += 1
        }
        XCTAssertTrue(element.isHittable, "\(element.identifier) is reachable on the page")
    }

    func testDownloadContinuesInTheBackgroundAndTheChatStaysUsable() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ARDemoData", "YES"]
        app.launch()
        let voice = app.buttons["Voice input"]
        XCTAssertTrue(voice.waitForExistence(timeout: 15))
        voice.tap()
        guard element(app, "voice-gate.title").waitForExistence(timeout: 5) else {
            throw XCTSkip("No speech model fits this simulator, so the voice button dictates at once")
        }
        let download = app.buttons["voice-gate.download"]
        XCTAssertTrue(download.waitForExistence(timeout: 5))
        download.tap()

        XCTAssertTrue(element(app, "voice-gate.title").waitForNonExistence(timeout: 5), "the cover closes at once")
        let input = element(app, "composer.input")
        XCTAssertTrue(input.waitForExistence(timeout: 5), "the chat is back")
        XCTAssertTrue(input.isHittable, "and not covered")

        // Opened again while it downloads: progress, not a second download.
        voice.tap()
        XCTAssertTrue(element(app, "voice-gate.progress").waitForExistence(timeout: 5), "the gate shows the running download")
        XCTAssertFalse(app.buttons["voice-gate.download"].exists, "no second download is offered")
        let background = app.buttons["voice-gate.background"]
        XCTAssertTrue(background.exists)
        background.tap()
        XCTAssertTrue(element(app, "voice-gate.title").waitForNonExistence(timeout: 5))

        app.revealSidebar(whenVisible: button(app, "Settings"))
        button(app, "Settings").tap()
        let models = button(app, "Local Models")
        XCTAssertTrue(models.waitForExistence(timeout: 10))
        models.tap()
        let link = app.buttons["local.voice"]
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        scrollUntilHittable(link, under: app.navigationBars["Local Models"])
        link.tap()
        XCTAssertTrue(app.navigationBars["Voice"].waitForExistence(timeout: 10))
        let progress = app.progressIndicators.matching(NSPredicate(format: "label BEGINSWITH %@", "Downloading")).firstMatch
        XCTAssertTrue(progress.waitForExistence(timeout: 10), "the speech model's row shows the progress")
        let cancel = app.buttons["Cancel"]
        XCTAssertTrue(cancel.exists, "and Cancel")
        cancel.tap()
        XCTAssertTrue(progress.waitForNonExistence(timeout: 10), "Cancel stops it")
    }
}
