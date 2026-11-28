import XCTest

/// Every menu that holds a Toggle draws it as a titled row with the system checkmark. A switch style set above a menu
/// made each toggle a titled row plus blank rows (lane B, 29ac88c), so this fails on any blank row a menu adds.
@MainActor
final class MenuToggleTests: XCTestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ARDemoData", "YES"]
        app.launch()
        return app
    }

    /// Buttons, switches and menu items on screen with no words: what a blank menu row looks like to XCUITest.
    private func blankRows(_ app: XCUIApplication) -> Int {
        let blank = NSPredicate(format: "label == '' AND identifier == ''")
        return [XCUIElement.ElementType.button, .switch, .menuItem].reduce(0) { total, type in
            total + app.descendants(matching: type).matching(blank).allElementsBoundByIndex.filter(\.isHittable).count
        }
    }

    private func expectNoBlankRows(_ app: XCUIApplication, before: Int, _ menu: String) {
        sleep(1)
        XCTAssertLessThanOrEqual(blankRows(app), before, "\(menu): every row of the menu has a title")
    }

    func testTheChatMoreMenuHasNoBlankRows() {
        let app = launch()
        let more = app.buttons["chat.more"]
        XCTAssertTrue(more.waitForExistence(timeout: 20))
        let before = blankRows(app)
        more.tap()
        expectNoBlankRows(app, before: before, "chat … menu")
    }

    func testThePlusMenuToolsSubmenuHasNoBlankRows() {
        let app = launch()
        let plus = app.buttons["Add"]
        XCTAssertTrue(plus.waitForExistence(timeout: 20))
        let before = blankRows(app)
        plus.tap()
        let tools = app.buttons["Tools"]
        XCTAssertTrue(tools.waitForExistence(timeout: 5), "the + menu has Tools")
        tools.tap()
        expectNoBlankRows(app, before: before, "+ menu › Tools")
    }

    func testTheModelFiltersMenuInLocalModelsHasNoBlankRows() {
        let app = launch()
        let gear = app.buttons["sidebar.settings"]
        app.revealSidebar(whenVisible: gear)
        gear.tap()
        let models = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Local Models")).firstMatch
        XCTAssertTrue(models.waitForExistence(timeout: 10))
        models.tap()
        let bar = app.navigationBars["Local Models"]
        XCTAssertTrue(bar.waitForExistence(timeout: 10))
        let browse = app.buttons["local.browse"]
        var tries = 0
        while !browse.isHittable && tries < 8 {
            let start = bar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).withOffset(CGVector(dx: 0, dy: 450))
            start.press(forDuration: 0.01, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -300)))
            tries += 1
        }
        browse.tap()
        let filter = app.buttons["hub.filter"]
        XCTAssertTrue(filter.waitForExistence(timeout: 10))
        let before = blankRows(app)
        filter.tap()
        expectNoBlankRows(app, before: before, "Browse all models › Filter")
    }
}
