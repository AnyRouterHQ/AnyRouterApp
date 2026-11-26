import XCTest

/// Theme: pick Dark in Settings, see it apply while the sheet is open, relaunch and see it persist; then Light.
@MainActor
final class ThemeJourney: JourneyCase {
    private func choose(_ theme: String, _ app: XCUIApplication) {
        openSettings(app)
        let row = button(app, containing: "Theme")
        reveal(row, in: app)
        row.tap()
        let option = app.buttons[theme]
        XCTAssertTrue(option.waitForExistence(timeout: 5), "\(theme) option")
        step("theme-page")
        option.tap()
        sleep(1)
        step("picked-\(theme.lowercased())-sheet-open")
    }

    func testThemePicksApplyLiveAndPersist() {
        continueAfterFailure = false
        let app = launch()
        XCTAssertTrue(app.buttons["Model"].waitForExistence(timeout: 15))
        step("home-system-theme")
        XCTAssertGreaterThan(brightness(), 0.6, "system theme starts light on the CI simulator")

        choose("Dark", app)
        XCTAssertLessThan(brightness(), 0.35, "Dark applies live while Settings is open")
        audit(app, "theme-page-dark")
        app.terminate()

        let relaunched = launch(keepSettings: true)
        XCTAssertTrue(relaunched.buttons["Model"].waitForExistence(timeout: 15))
        step("relaunch-dark-persisted")
        XCTAssertLessThan(brightness(), 0.35, "Dark survives a relaunch")

        choose("Light", relaunched)
        XCTAssertGreaterThan(brightness(), 0.6, "Light applies live while Settings is open")
        relaunched.terminate()

        let again = launch(keepSettings: true)
        XCTAssertTrue(again.buttons["Model"].waitForExistence(timeout: 15))
        step("relaunch-light-persisted")
        XCTAssertGreaterThan(brightness(), 0.6, "Light survives a relaunch")
        again.terminate()
    }
}
