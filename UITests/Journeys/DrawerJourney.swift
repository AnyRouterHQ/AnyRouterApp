import XCTest

/// Sidebar: open, search (keyboard up, list filters), pick a thread, start a new chat.
@MainActor
final class DrawerJourney: JourneyCase {
    func testDrawerSearchSelectAndNewChat() {
        runPasses { app, _ in
            XCTAssertTrue(app.buttons["Model"].waitForExistence(timeout: 15))
            openSidebar(app)
            XCTAssertTrue(app.staticTexts["Explain Swift actors"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["Trip ideas for Lisbon"].exists, "pinned thread is listed")
            step("drawer-open")
            audit(app, "drawer")

            let search = app.searchFields["Search chats"]
            search.tap()
            XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: 5), "search focus raises the keyboard")
            search.typeText("swift")
            let gone = NSPredicate(format: "exists == false")
            expectation(for: gone, evaluatedWith: app.staticTexts["Trip ideas for Lisbon"])
            waitForExpectations(timeout: 5)
            XCTAssertTrue(app.staticTexts["Explain Swift actors"].exists, "matching thread stays")
            step("search-filtered")

            app.buttons["Clear text"].tap()
            XCTAssertTrue(app.staticTexts["Trip ideas for Lisbon"].waitForExistence(timeout: 5), "clearing the query restores the list")
            step("search-cleared")

            app.staticTexts["Explain Swift actors"].tap()
            XCTAssertTrue(app.staticTexts["Key points:"].waitForExistence(timeout: 10), "thread opens with its answer")
            step("thread-opened")

            let newChat = visibleButton(app, "New chat")
            XCTAssertTrue(newChat.waitForExistence(timeout: 5), "New chat button is on screen")
            newChat.tap()
            XCTAssertTrue(app.staticTexts["What can I help with?"].waitForExistence(timeout: 10), "new chat shows home")
            step("new-chat-home")
        }
    }
}
