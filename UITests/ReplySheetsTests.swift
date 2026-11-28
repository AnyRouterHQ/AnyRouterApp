import XCTest

/// The sheets under a finished reply's footer: the sources list, the details of a reply, and the memories a reply used.
/// Each opens from the footer row and closes again. Demo data; no page is opened in Safari.
@MainActor
final class ReplySheetsTests: XCTestCase {
    private func openChat(titled title: String, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication.launchedOnDemoData(extra: extra)
        let row = app.staticTexts[title]
        app.revealSidebar(whenVisible: row)
        XCTAssertTrue(FlowWait.until(10) { row.isHittable }, "\(title) can take a tap")
        row.tap()
        return app
    }

    func testSourcesOpenAsAListOfPagesAndCloseAgain() {
        let app = openChat(titled: "Swift actors with sources", extra: ["-ARDemoSources", "YES"])
        let sources = app.buttons["reply.sources"].firstMatch
        XCTAssertTrue(sources.waitForExistence(timeout: 15), "the reply's footer has its sources")
        XCTAssertEqual(sources.label, "5 sources", "six results, one of them the same page twice")
        sources.tap()
        XCTAssertTrue(app.navigationBars["Sources"].waitForExistence(timeout: 5), "the sources sheet opened")
        XCTAssertTrue(app.labelled(containing: "docs.example.com").waitForExistence(timeout: 5), "the list names each page and its host")
        app.navigationBars["Sources"].buttons["Close"].tap()
        XCTAssertTrue(app.navigationBars["Sources"].waitForNonExistence(timeout: 5), "Close dismisses the sheet")
    }

    func testTheDetailsOfAReplyOpenFromItsFooterLine() {
        let app = openChat(titled: "Switch models in a chat")
        let paid = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "$0.0004")).firstMatch
        XCTAssertTrue(paid.waitForExistence(timeout: 15), "the paid reply shows its price in the footer line")
        paid.tap()
        XCTAssertTrue(app.navigationBars["Reply details"].waitForExistence(timeout: 5), "the details sheet opened")
        XCTAssertTrue(app.buttons["reply.details.copy-all"].exists, "it offers Copy all")
        app.navigationBars["Reply details"].buttons["Close"].tap()
        XCTAssertTrue(app.navigationBars["Reply details"].waitForNonExistence(timeout: 5), "Close dismisses the sheet")
    }

    func testAReplyThatUsedAMemoryListsItAndForgetStrikesItThrough() {
        let app = XCUIApplication.launchedOnDemoData(extra: ["-ARDemoMemories", "YES"])
        let input = app.element(UITestIDs.composerInput)
        XCTAssertTrue(input.waitForExistence(timeout: 15))
        input.tap()
        input.typeText("What is my dog called")
        app.buttons["Send"].tap()

        let used = app.buttons["reply.memories"].firstMatch
        XCTAssertTrue(used.waitForExistence(timeout: 30), "the reply says it used a memory")
        used.tap()
        XCTAssertTrue(app.navigationBars["Memories used"].waitForExistence(timeout: 5), "the memories sheet opened")
        let memory = app.staticTexts["My dog is called Mochi."]
        XCTAssertTrue(memory.waitForExistence(timeout: 5), "it lists the memory the reply used")
        memory.swipeLeft()
        let forget = app.buttons["Forget"].firstMatch
        XCTAssertTrue(forget.waitForExistence(timeout: 5), "a swipe offers Forget")
        forget.tap()
        XCTAssertTrue(forget.waitForNonExistence(timeout: 5), "a forgotten memory has nothing left to forget")
    }
}
