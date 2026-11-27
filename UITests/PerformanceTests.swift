import XCTest

/// Performance baseline, see PLAN.md § Native UX & performance (M1 to M5).
/// Run on a Release build. Each test launches the app itself and measures only the interesting part.
/// XCTHitchMetric is not used: it reports nothing on the Simulator (checked in CI), so hitches need a device.
/// Signpost names come from `App/Perf.swift`.
@MainActor
final class PerformanceTests: XCTestCase {
    private static let subsystem = "dev.anyrouter.app"
    private static let category = "perf"

    private func signpost(_ name: String) -> XCTOSSignpostMetric {
        XCTOSSignpostMetric(subsystem: Self.subsystem, category: Self.category, name: name)
    }

    /// XCTCPUMetric and XCTMemoryMetric bind to the process that is running when an iteration starts, so a test that
    /// uses them launches the app before `measure` and never terminates it inside the block.
    private func options(iterations: Int = 5) -> XCTMeasureOptions {
        let options = XCTMeasureOptions()
        options.iterationCount = iterations
        return options
    }

    private func demoApp(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ARDemoData", "YES", "-ARAppearance", "light"] + extra
        return app
    }

    /// M1. The real launch path: real container, Keychain, background session. No demo data.
    /// `-settings.onboarded YES` skips the onboarding cover so every iteration shows the chat.
    func testColdLaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["-settings.onboarded", "YES"]
        let metrics: [XCTMetric] = [
            XCTApplicationLaunchMetric(waitUntilResponsive: true),
            signpost("launch.container"), signpost("launch.engines"), signpost("launch.auth"), signpost("launch.hub"),
        ]
        measure(metrics: metrics, options: options()) {
            app.launch()
            app.terminate()
        }
    }

    /// M5. Cloud list answers after 5 s. The baseline shows how long Apple and local models stay unusable.
    func testFirstUsableModelWithSlowCloud() {
        let app = demoApp(["-ARDemoCloudDelay", "5"])
        measure(metrics: [signpost("models.firstUsable")], options: options(iterations: 3)) {
            app.launch()
            sleep(7)
            app.terminate()
        }
    }

    /// M2. App CPU time for fast swipes up and down a 200-message thread that opens at launch.
    func testScrollLongThread() {
        let app = demoApp(["-ARDemoLongThread", "200"])
        app.launch()
        XCTAssertTrue(app.buttons["Model"].waitForExistence(timeout: 20))
        sleep(2)
        measure(metrics: [XCTCPUMetric(application: app)], options: options(iterations: 3)) {
            for _ in 0..<4 { app.swipeDown(velocity: .fast) }
            for _ in 0..<4 { app.swipeUp(velocity: .fast) }
        }
        app.terminate()
    }

    /// M3. One reply of 1,000 tokens at 50 per second (about 20 s). One launch, a new chat per iteration so history stays short.
    /// The app is launched before `measure` because XCTCPUMetric binds to the process that is running when measuring starts.
    func testStreamReply() {
        let app = demoApp(["-ARDemoStream", "1000@50"])
        app.launch()
        let metrics: [XCTMetric] = [XCTCPUMetric(application: app), XCTMemoryMetric(application: app), signpost("row.assistant")]
        // Manual start/stop makes XCTCPUMetric fail to harvest on the Simulator (checked in CI), so the whole block is
        // measured: about 3 s of tapping and typing plus the stream. The idle control has the same length.
        measure(metrics: metrics, options: options(iterations: 3)) {
            // isHittable is not a key path XCUITest predicates accept (bakeoff perf 46065091039 failed on it), so filter here.
            app.buttons.matching(NSPredicate(format: "label == 'New chat'")).allElementsBoundByIndex.first { $0.isHittable }?.tap()
            send("Write something long", in: app)
            XCTAssertTrue(app.buttons["Regenerate"].waitForExistence(timeout: 90), "reply did not finish")
        }
        app.terminate()
    }

    /// M3 control: 20 s with nothing streaming, about the length of `testStreamReply`. Subtract its CPU from it.
    func testIdleControl() {
        let app = demoApp(["-ARDemoStream", "1000@50"])
        app.launch()
        XCTAssertTrue(app.buttons["Model"].waitForExistence(timeout: 20))
        sleep(2)
        measure(metrics: [XCTCPUMetric(application: app), XCTMemoryMetric(application: app)], options: options(iterations: 3)) {
            sleep(20)
        }
        app.terminate()
    }

    /// M4. Time from the tap until the AnyRouter tab shows its first row, then picking that row, which closes the
    /// sheet. The block includes XCUITest reading the screen, which grows with the number of rows, so the
    /// 6-model control below tells how much of the 500-model number is the list itself.
    func testPickerOpenWith500Models() {
        measurePicker(extra: ["-ARDemoManyModels", "500"])
    }

    /// M4 control: the same steps with the six demo cloud models.
    func testPickerOpenWith6Models() {
        measurePicker(extra: [])
    }

    private func measurePicker(extra: [String]) {
        let app = demoApp(extra)
        app.launch()
        XCTAssertTrue(app.buttons["Model"].waitForExistence(timeout: 20))
        sleep(2)
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'model-row.'"))
        // Whole block measured, closing the sheet included: manual start/stop breaks XCTCPUMetric on the Simulator.
        measure(metrics: [XCTClockMetric(), XCTCPUMetric(application: app)], options: options()) {
            app.buttons["Model"].tap()
            let tabs = app.segmentedControls.firstMatch
            XCTAssertTrue(tabs.waitForExistence(timeout: 30))
            tabs.buttons["AnyRouter"].tap()
            XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 30))
            rows.firstMatch.tap()
            XCTAssertTrue(tabs.waitForNonExistence(timeout: 10), "picker did not close")
        }
        app.terminate()
    }

    private func send(_ text: String, in app: XCUIApplication) {
        XCTAssertTrue(app.buttons["Model"].waitForExistence(timeout: 20))
        sleep(2)
        let field = app.textViews.firstMatch.exists ? app.textViews.firstMatch : app.textFields.firstMatch
        field.tap()
        field.typeText(text)
        app.buttons["Send"].tap()
    }
}
