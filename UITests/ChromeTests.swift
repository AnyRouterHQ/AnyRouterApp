import XCTest

/// The chat chrome: a bare model title between two system buttons, and one round button at the end of the composer.
/// Uses demo data; the stream is slow enough to see the stop state.
@MainActor
final class ChromeTests: XCTestCase {
    private func launch(stream: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ARDemoData", "YES"] + (stream ? ["-ARDemoStream", "1000@20"] : [])
        app.launch()
        return app
    }

    func testTitleNamesTheModelAndOpensThePicker() {
        let app = launch()
        let title = app.buttons["Model"]
        XCTAssertTrue(title.waitForExistence(timeout: 15))
        let name = title.value as? String ?? ""
        XCTAssertFalse(name.isEmpty, "the title says which model is selected")
        title.tap()
        XCTAssertTrue(app.segmentedControls.firstMatch.waitForExistence(timeout: 5), "the picker opens")
    }

    func testTopBarHoldsOnlyTheSidebarTitleMoreAndNewChat() throws {
        let app = launch()
        try XCTSkipIf(!app.buttons["Menu"].waitForExistence(timeout: 15), "iPad layout: the system adds its own sidebar toggle")
        let bar = app.navigationBars.firstMatch
        XCTAssertTrue(bar.buttons["Model"].exists)
        // The glass group around "More" and "New chat" shows up as one unlabeled button; it is not a control of its own.
        let labels = bar.buttons.allElementsBoundByIndex.map(\.label).filter { !$0.isEmpty }.sorted()
        XCTAssertEqual(labels, ["Menu", "Model", "More", "New chat"], "the sidebar, the title, the more menu and new chat; nothing else")
    }

    func testRoundButtonGoesVoiceThenSendThenStop() {
        let app = launch(stream: true)
        let input = app.descendants(matching: .any)["composer.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["Voice input"].exists, "empty field offers voice")
        XCTAssertFalse(app.buttons["Send"].exists)

        input.tap()
        input.typeText("hello")
        XCTAssertTrue(app.buttons["Send"].waitForExistence(timeout: 5), "text turns it into send")
        XCTAssertFalse(app.buttons["Voice input"].exists)

        app.buttons["Send"].tap()
        XCTAssertTrue(app.buttons["Stop"].waitForExistence(timeout: 10), "a reply in progress shows stop")

        app.buttons["Stop"].tap()
        XCTAssertTrue(app.buttons["Voice input"].waitForExistence(timeout: 10), "stopping returns to voice")
    }

    func testPresetsAndAttachmentsLiveInThePlusMenu() {
        let app = launch()
        XCTAssertTrue(app.buttons["Add"].waitForExistence(timeout: 15))
        app.buttons["Add"].tap()
        XCTAssertTrue(app.buttons["composer.presets"].waitForExistence(timeout: 5), "presets moved here from the field")
        XCTAssertTrue(app.buttons["composer.add-photos"].exists)
    }
}
