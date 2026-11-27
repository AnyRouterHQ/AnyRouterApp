import XCTest

/// Settings, Responses, "Show response details": the line under each reply (model, first token, speed)
/// is there by default, goes away when the toggle is off and stays away after a relaunch.
@MainActor
final class ResponseDetailsJourney: JourneyCase {
    private func send(_ text: String, _ app: XCUIApplication) {
        let input = composer(app)
        input.tap()
        input.typeText(text)
        app.buttons["Send"].tap()
        XCTAssertTrue(app.staticTexts["This is a demo reply."].waitForExistence(timeout: 10), "demo reply")
    }

    private func setToggle(_ on: Bool, _ app: XCUIApplication) {
        openSettings(app)
        let row = button(app, containing: "Responses")
        reveal(row, in: app)
        row.tap()
        let toggle = app.switches["settings-show-response-details"]
        reveal(toggle, in: app)
        if (toggle.value as? String == "1") != on {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        }
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", on ? "1" : "0"), object: toggle)
        XCTAssertEqual(XCTWaiter().wait(for: [expected], timeout: 5), .completed, "toggle did not change")
        step("toggle-\(on ? "on" : "off")")
        audit(app, "response-customization")
        // "Close" belongs to the Settings root; this page is pushed on top of it, so go back first.
        let back = app.buttons["BackButton"]
        if back.exists { back.tap() }
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 5), "Settings root shows Close")
        app.buttons["Close"].tap()
        sleep(1)
    }

    func testResponseDetailsToggleShowsHidesAndPersists() {
        runPasses([.light, .dark]) { app, pass in
            XCTAssertTrue(app.buttons["Model"].waitForExistence(timeout: 15))
            send("Hello there", app)
            let details = app.descendants(matching: .any)["response-details"]
            XCTAssertTrue(details.waitForExistence(timeout: 5), "details line is shown by default")
            step("details-default-on")

            setToggle(false, app)
            XCTAssertTrue(waitGone(details, timeout: 5), "turning the toggle off hides the line at once")
            step("details-hidden")
            app.terminate()

            let relaunched = launch(pass.launchArguments, keepSettings: true)
            XCTAssertTrue(relaunched.buttons["Model"].waitForExistence(timeout: 15))
            send("Hello again", relaunched)
            sleep(1)
            XCTAssertFalse(relaunched.descendants(matching: .any)["response-details"].exists, "the choice survives a relaunch")
            step("relaunch-details-still-hidden")

            setToggle(true, relaunched)
            XCTAssertTrue(relaunched.descendants(matching: .any)["response-details"].waitForExistence(timeout: 5), "turning it back on shows the line")
            step("details-back-on")
        }
    }
}
