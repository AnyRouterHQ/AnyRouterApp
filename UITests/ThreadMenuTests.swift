import XCTest

/// The long-press menu on a chat row in the sidebar (demo data).
@MainActor
final class ThreadMenuTests: XCTestCase {
    private let title = "Dinner with chickpeas"

    func testLongPressShowsTheMenuAndArchiveMovesTheChatToArchivedChats() {
        let app = XCUIApplication()
        app.launchArguments = ["-ARDemoData", "YES"]
        app.launch()
        let row = app.staticTexts[title]
        app.revealSidebar(whenVisible: row)
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.press(forDuration: 1.2)

        for id in ["pin", "rename", "share", "archive", "delete"] {
            XCTAssertTrue(app.descendants(matching: .any)["thread.menu.\(id)"].waitForExistence(timeout: 5), "menu item \(id)")
        }
        app.buttons["thread.menu.archive"].tap()
        XCTAssertTrue(XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: row).waitUntilFulfilled(), "the chat leaves Recents")

        let search = app.buttons["sidebar.search"]
        app.revealSidebar(whenVisible: search)
        search.tap()
        let archived = app.descendants(matching: .any)["search.archived"]
        XCTAssertTrue(archived.waitForExistence(timeout: 10), "View all ends with Archived chats")
        archived.tap()
        XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 5), "the chat is in Archived chats")
    }
}

private extension XCTNSPredicateExpectation {
    func waitUntilFulfilled(timeout: TimeInterval = 5) -> Bool {
        XCTWaiter().wait(for: [self], timeout: timeout) == .completed
    }
}
