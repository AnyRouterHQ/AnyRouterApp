import UIKit
import XCTest

/// iPad layouts on demo data: the sidebar column, the readable chat width, the model popover, form and page
/// sheets, rotation, and the compact-width fallback. Skipped on iPhone. Run on an iPad mini and an iPad Pro 13
/// by .github/workflows/verify-ui.yml (nightly, and with `-f ipad=true`).
@MainActor
final class PadLayoutTests: XCTestCase {
    /// Same as `ARTheme.contentMaxWidth`: the chat column, margins included.
    private let columnCap: CGFloat = 720

    override func setUpWithError() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "iPad layouts")
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        XCUIDevice.shared.orientation = .portrait
    }

    private func launch(_ extra: [String] = [], orientation: UIDeviceOrientation) -> XCUIApplication {
        XCUIDevice.shared.orientation = orientation
        let app = XCUIApplication()
        app.launchArguments = ["-ARDemoData", "YES"] + extra
        app.launch()
        return app
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func sidebarIsVisible(_ app: XCUIApplication) -> Bool {
        let compose = element(app, "sidebar.compose")
        return compose.exists && compose.isHittable
    }

    private func wait(timeout: TimeInterval = 8, _ condition: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return condition()
    }

    // MARK: Shell

    func testSidebarIsBesideTheChatInLandscapeAndTheToolbarTogglesIt() {
        let app = launch(orientation: .landscapeLeft)
        XCTAssertTrue(element(app, "composer.input").waitForExistence(timeout: 15))
        XCTAssertTrue(wait { sidebarIsVisible(app) }, "landscape shows the sidebar by default")
        XCTAssertFalse(app.buttons["Menu"].exists, "the drawer button is the iPhone path")

        XCTAssertTrue(app.sidebarToggle.waitForExistence(timeout: 5))
        app.sidebarToggle.tap()
        XCTAssertTrue(wait { !sidebarIsVisible(app) }, "the toggle hides the sidebar")
        app.sidebarToggle.tap()
        XCTAssertTrue(wait { sidebarIsVisible(app) }, "the toggle shows it again")
    }

    func testSidebarStartsTuckedAwayInPortraitOpensOverTheChatAndClosesOnPick() {
        let app = launch(orientation: .portrait)
        XCTAssertTrue(element(app, "composer.input").waitForExistence(timeout: 15))
        XCTAssertFalse(sidebarIsVisible(app), "portrait starts with the chat alone")

        XCTAssertTrue(app.sidebarToggle.waitForExistence(timeout: 5))
        app.sidebarToggle.tap()
        XCTAssertTrue(wait { sidebarIsVisible(app) })

        app.staticTexts["Explain Swift actors"].tap()
        XCTAssertTrue(app.staticTexts["Key points:"].waitForExistence(timeout: 10))
        XCTAssertTrue(wait { !sidebarIsVisible(app) }, "picking a chat closes the overlay")
    }

    func testRotationKeepsTheChatAndTheDraft() {
        let app = launch(["-ARDemoLongThread", "8"], orientation: .portrait)
        let input = element(app, "composer.input")
        XCTAssertTrue(input.waitForExistence(timeout: 15))
        input.tap()
        input.typeText("draft text")

        for orientation in [UIDeviceOrientation.landscapeLeft, .portrait] {
            XCUIDevice.shared.orientation = orientation
            XCTAssertTrue(element(app, "chat.content").waitForExistence(timeout: 10), "the open chat stays")
            XCTAssertTrue(wait { element(app, "composer.input").value as? String == "draft text" }, "the draft stays")
        }
    }

    func testCompactWidthTakesThePhoneLayout() {
        // Split View and Slide Over cannot be scripted; -ARSizeClass compact gives the app the size class they give it.
        let app = launch(["-ARSizeClass", "compact"], orientation: .landscapeLeft)
        XCTAssertTrue(app.buttons["Menu"].waitForExistence(timeout: 15), "compact width keeps the drawer button")
        app.buttons["Menu"].tap()
        // The header sits in the top bar; the bottom-bar compose button is not laid out the iPhone way under a forced size class.
        XCTAssertTrue(element(app, "sidebar.header").waitForExistence(timeout: 8), "the drawer opens")
        XCTAssertTrue(element(app, "main.container").exists, "the phone shell is on screen")
    }

    // MARK: Chat column

    func testChatColumnIsCappedAndCentered() {
        for orientation in [UIDeviceOrientation.landscapeLeft, .portrait] {
            let app = launch(["-ARDemoLongThread", "8"], orientation: orientation)
            let content = element(app, "chat.content")
            let detail = element(app, "chat.detail")
            XCTAssertTrue(content.waitForExistence(timeout: 15))
            XCTAssertTrue(detail.exists)
            XCTAssertLessThanOrEqual(content.frame.width, columnCap, "messages stay inside the cap")
            XCTAssertGreaterThan(content.frame.width, 600, "and use the room up to it")
            XCTAssertEqual(content.frame.midX, detail.frame.midX, accuracy: 2, "centered in the chat column")
            XCTAssertLessThanOrEqual(element(app, "composer.input").frame.width, columnCap, "the composer too")
            app.terminate()
        }
    }

    // MARK: Presentations

    func testModelPickerIsAPopoverUnderThePill() {
        let app = launch(orientation: .landscapeLeft)
        let pill = app.buttons["Model"]
        XCTAssertTrue(pill.waitForExistence(timeout: 15))
        pill.tap()
        let popover = app.popovers.firstMatch
        XCTAssertTrue(popover.waitForExistence(timeout: 5), "a popover, not a sheet")
        XCTAssertTrue(popover.segmentedControls.firstMatch.exists)
        XCTAssertLessThan(popover.frame.width, app.windows.firstMatch.frame.width / 2)
        XCTAssertGreaterThanOrEqual(popover.frame.minY, pill.frame.midY, "it hangs below the pill")

        popover.buttons["Close"].tap()
        XCTAssertTrue(wait { !app.popovers.firstMatch.exists })
    }

    func testCmdKOpensTheModelPicker() {
        let app = launch(orientation: .landscapeLeft)
        XCTAssertTrue(app.buttons["Model"].waitForExistence(timeout: 15))
        app.typeKey("k", modifierFlags: .command)
        XCTAssertTrue(app.popovers.firstMatch.waitForExistence(timeout: 5), "Cmd K opens the picker")
    }

    func testSettingsIsAFormSheetNotFullWidth() {
        let app = launch(orientation: .landscapeLeft)
        let settings = element(app, "sidebar.settings")
        XCTAssertTrue(settings.waitForExistence(timeout: 15))
        settings.tap()
        let bar = app.navigationBars["Settings"]
        XCTAssertTrue(bar.waitForExistence(timeout: 5))
        XCTAssertLessThan(bar.frame.width, app.windows.firstMatch.frame.width * 0.7, "a form-sized sheet")
    }

    func testBrowseModelsIsAPageSheetNotFullWidth() {
        let app = launch(orientation: .landscapeLeft)
        let pill = app.buttons["Model"]
        XCTAssertTrue(pill.waitForExistence(timeout: 15))
        pill.tap()
        let popover = app.popovers.firstMatch
        XCTAssertTrue(popover.waitForExistence(timeout: 5))
        popover.segmentedControls.firstMatch.buttons["Local"].tap()
        let browse = popover.buttons["Browse models"]
        XCTAssertTrue(browse.waitForExistence(timeout: 5))
        browse.tap()
        let bar = app.navigationBars["Local Models"]
        XCTAssertTrue(bar.waitForExistence(timeout: 10))
        XCTAssertLessThan(bar.frame.width, app.windows.firstMatch.frame.width - 40, "inset from the screen edges")
    }

    // MARK: Hardware keyboard

    func testCmdNStartsANewChat() {
        let app = launch(["-ARDemoLongThread", "8"], orientation: .landscapeLeft)
        XCTAssertTrue(element(app, "chat.content").waitForExistence(timeout: 15))
        // A key press right after launch can land before the scene is the key window, so one retry.
        app.typeKey("n", modifierFlags: .command)
        if !element(app, "home.greeting").waitForExistence(timeout: 4) {
            app.typeKey("n", modifierFlags: .command)
        }
        XCTAssertTrue(element(app, "home.greeting").waitForExistence(timeout: 6), "an empty chat opens")
    }
}
