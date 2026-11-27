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
        XCTAssertTrue(app.buttons["composer.add-camera"].exists)
        XCTAssertTrue(app.buttons["composer.add-photos"].exists)
        XCTAssertTrue(app.buttons["composer.add-files"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["composer.tool-source.device"].exists, "source switches wait under Tools")
        let tools = app.buttons["composer.tools"]
        XCTAssertEqual(tools.exists, app.buttons["composer.plugins"].exists, "Tools shows for every model that takes tools")
        guard tools.exists else { return }
        tools.tap()
        XCTAssertTrue(app.descendants(matching: .any)["composer.tools-toggle"].waitForExistence(timeout: 5), "the chat's switch comes first")
        let device = app.descendants(matching: .any)["composer.tool-group.device"]
        XCTAssertTrue(device.waitForExistence(timeout: 5), "one submenu per source group")
        device.tap()
        XCTAssertTrue(app.descendants(matching: .any)["composer.tool-source.device"].waitForExistence(timeout: 5))
    }

    /// Every row of the Tools submenu and of a source's submenu shows its title. A switch style that leaked into the menu
    /// once split each toggle into a titled row and two blank checkmark rows (screenshots 46075429647).
    func testEveryToolsMenuRowHasATitle() {
        let app = launch()
        XCTAssertTrue(app.buttons["Add"].waitForExistence(timeout: 15))
        app.buttons["Add"].tap()
        let tools = app.buttons["composer.tools"]
        XCTAssertTrue(tools.waitForExistence(timeout: 5), "the demo model takes tools")
        tools.tap()
        let chatSwitch = app.descendants(matching: .any)["composer.tools-toggle"]
        XCTAssertTrue(chatSwitch.waitForExistence(timeout: 5))
        assertMenuRowsHaveTitles(app, from: chatSwitch)

        app.descendants(matching: .any)["composer.tool-group.device"].tap()
        let source = app.descendants(matching: .any)["composer.tool-source.device"]
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        XCTAssertEqual(source.label, "Use On this device tools", "the source's own switch, not a copy of the submenu title")
        let toolRows = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "composer.tool.builtin/")).allElementsBoundByIndex
        XCTAssertFalse(toolRows.isEmpty, "the device's tools are listed")
        for row in toolRows { XCTAssertFalse(row.label.isEmpty, "\(row.identifier) has no title") }
        assertMenuRowsHaveTitles(app, from: source)
    }

    /// Every control in the open menu's column, from `first` down, has a label. Menu rows share the first row's x and width.
    private func assertMenuRowsHaveTitles(_ app: XCUIApplication, from first: XCUIElement, line: UInt = #line) {
        let column = first.frame
        let types: [XCUIElement.ElementType] = [.button, .switch, .toggle, .menuItem]
        let controls = app.descendants(matching: .any)
            .matching(NSPredicate(format: "elementType IN %@", types.map { NSNumber(value: $0.rawValue) }))
            .allElementsBoundByIndex
        let rows = controls.filter {
            abs($0.frame.minX - column.minX) < 1 && abs($0.frame.width - column.width) < 1 && $0.frame.minY >= column.minY - 1
        }
        XCTAssertFalse(rows.isEmpty, "the menu's rows are found", line: line)
        for row in rows {
            XCTAssertFalse(row.label.isEmpty, "a menu row at \(NSCoder.string(for: row.frame)) has no title", line: line)
        }
    }

    /// The + is a circle as tall as the one-line field and centred on it.
    func testPlusIsAsTallAsTheFieldAndCentredOnIt() {
        let app = launch()
        let plus = app.buttons["Add"]
        let input = app.descendants(matching: .any)["composer.input"]
        XCTAssertTrue(plus.waitForExistence(timeout: 15) && input.waitForExistence(timeout: 5))
        let send = app.buttons["composer.action"]
        XCTAssertEqual(plus.frame.height, 48, accuracy: 2)
        XCTAssertEqual(plus.frame.width, plus.frame.height, accuracy: 1)
        XCTAssertEqual(plus.frame.midY, send.frame.midY, accuracy: 2, "the + and the field's button sit on one line")
    }
}
