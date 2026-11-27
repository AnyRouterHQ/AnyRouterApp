import XCTest

/// Sidebar: open, search (the search button opens a full-screen search with the keyboard up), pick a thread, start a new chat.
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

            app.buttons["sidebar.search"].tap()
            let field = app.searchFields["Search chats"]
            XCTAssertTrue(field.waitForExistence(timeout: 5), "search screen opens")
            XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: 5), "the keyboard is up as soon as search opens")
            step("search-open")
            field.typeText("swift")
            XCTAssertTrue(waitGone(button(app, containing: "Trip ideas for Lisbon"), timeout: 5), "non-matching thread leaves the list")
            XCTAssertTrue(button(app, containing: "Explain Swift actors").waitForExistence(timeout: 5), "matching thread stays")
            step("search-filtered")

            button(app, containing: "Explain Swift actors").tap()
            XCTAssertTrue(app.replyText("Key points:").waitForExistence(timeout: 10), "thread opens with its answer")
            step("thread-opened")

            let newChat = visibleButton(app, "New chat")
            XCTAssertTrue(newChat.waitForExistence(timeout: 5), "New chat button is on screen")
            newChat.tap()
            XCTAssertTrue(greeting(app).waitForExistence(timeout: 10), "new chat shows home")
            step("new-chat-home")
        }
    }
}
