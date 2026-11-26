import XCTest

/// Settings: drill into pages and back, flip "Show keyboard on launch" and see it take effect after a relaunch.
@MainActor
final class SettingsJourney: JourneyCase {
    private func setKeyboardToggle(_ on: Bool, _ app: XCUIApplication) {
        openSettings(app)
        let toggle = app.switches["settings-show-keyboard"]
        reveal(toggle, in: app)
        if (toggle.value as? String == "1") != on {
            // Tap the switch itself, at the trailing edge of the row.
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        }
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", on ? "1" : "0"), object: toggle)
        XCTAssertEqual(XCTWaiter().wait(for: [expected], timeout: 5), .completed, "toggle did not change")
        step("keyboard-toggle-\(on ? "on" : "off")")
    }

    func testDrillDownAndKeyboardToggleSurvivesRelaunch() {
        runPasses([.light, .dark]) { app, pass in
            XCTAssertTrue(app.buttons["Model"].waitForExistence(timeout: 15))
            openSettings(app)
            step("settings-root")
            audit(app, "settings-root")

            for page in ["Inference", "Privacy"] {
                let row = button(app, containing: page)
                reveal(row, in: app)
                row.tap()
                XCTAssertTrue(app.navigationBars[page].waitForExistence(timeout: 5), "\(page) page")
                step("page-\(page.lowercased())")
                app.buttons["BackButton"].tap()
                if !app.navigationBars["Settings"].waitForExistence(timeout: 5) { fail(app, "back-did-not-return", "back at the Settings list") }
            }
            app.terminate()

            // Persistence, with the pass appearance carried over the relaunch.
            let on = launch(pass.launchArguments)
            setKeyboardToggle(true, on)
            on.terminate()
            let relaunchedOn = launch(pass.launchArguments, keepSettings: true)
            XCTAssertTrue(relaunchedOn.keyboards.element.waitForExistence(timeout: 15), "keyboard is up at launch when the toggle is on")
            step("relaunch-keyboard-up")
            relaunchedOn.terminate()

            let off = launch(pass.launchArguments, keepSettings: true)
            XCTAssertTrue(off.keyboards.element.waitForExistence(timeout: 15))
            off.buttons["Menu"].tap()
            setKeyboardToggle(false, off)
            off.terminate()
            let relaunchedOff = launch(pass.launchArguments, keepSettings: true)
            XCTAssertTrue(relaunchedOff.buttons["Model"].waitForExistence(timeout: 15))
            sleep(2)
            XCTAssertEqual(relaunchedOff.keyboards.count, 0, "no keyboard at launch when the toggle is off")
            step("relaunch-keyboard-down")
        }
    }
}
