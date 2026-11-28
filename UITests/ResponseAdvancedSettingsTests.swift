import XCTest

/// Settings > Responses > Advanced: moving the temperature slider changes it, and Reset to defaults puts it back.
@MainActor
final class ResponseAdvancedSettingsTests: XCTestCase {
    func testTemperatureMovesAndResetToDefaultsPutsItBack() {
        let app = XCUIApplication.launchedOnDemoData()
        app.showSettingsPage("Responses")
        let advanced = app.buttons["settings-response-advanced"]
        app.scrollPage(under: app.navigationBars["Responses"], until: advanced)
        XCTAssertTrue(advanced.isHittable, "Advanced is reachable on the Responses page")
        advanced.tap()
        XCTAssertTrue(app.navigationBars["Advanced"].waitForExistence(timeout: 10), "the Advanced page opened")

        let temperature = app.sliders["settings-temperature"]
        XCTAssertTrue(temperature.waitForExistence(timeout: 5), "the temperature slider is on the page")
        let before = temperature.value as? String ?? ""
        temperature.adjust(toNormalizedSliderPosition: 0.95)
        XCTAssertTrue(FlowWait.until(5) { (temperature.value as? String ?? "") != before }, "the slider moved from \(before)")

        let reset = app.buttons["Reset to defaults"]
        app.scrollPage(under: app.navigationBars["Advanced"], until: reset)
        reset.tap()
        XCTAssertTrue(FlowWait.until(5) { (temperature.value as? String ?? "") == before }, "Reset to defaults put the slider back at \(before)")
    }
}
