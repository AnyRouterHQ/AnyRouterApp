import XCTest

/// Composer: focus raises the keyboard, typing enables Send, sending shows the reply, a tap on the list dismisses the keyboard.
@MainActor
final class ComposerJourney: JourneyCase {
    func testTypeSendAndDismissKeyboard() {
        runPasses { app, _ in
            XCTAssertTrue(greeting(app).waitForExistence(timeout: 15))
            step("home")
            let subtitle = app.staticTexts["home.subtitle"]
            let before = subtitle.label
            greeting(app).tap()
            sleep(1)
            XCTAssertNotEqual(subtitle.label, before, "tapping the greeting swaps the subtitle for a tip")
            step("home-tip")
            audit(app, "home")

            let input = composer(app)
            input.tap()
            XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: 5), "tapping the field raises the keyboard")
            input.typeText("Hello there")
            let send = app.buttons["Send"]
            XCTAssertTrue(send.waitForExistence(timeout: 5))
            XCTAssertTrue(send.isEnabled, "text enables Send")
            step("typed")

            send.tap()
            XCTAssertTrue(app.staticTexts["Hello there"].waitForExistence(timeout: 10), "user message appears")
            XCTAssertTrue(app.staticTexts["This is a demo reply."].waitForExistence(timeout: 10), "demo reply appears")
            step("sent-and-replied")
            audit(app, "conversation")

            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
            let hidden = NSPredicate(format: "count == 0")
            expectation(for: hidden, evaluatedWith: app.keyboards)
            waitForExpectations(timeout: 5)
            step("keyboard-dismissed")
        }
    }
}
