import XCTest

/// A long press on a reply selects its words in place, with the system's Copy, instead of a separate Select Text sheet.
@MainActor
final class ReplySelectionTests: XCTestCase {
    func testALongPressOnAReplySelectsTextWithTheSystemCopy() {
        let app = XCUIApplication()
        app.launchArguments = ["-ARDemoData", "YES"]
        app.launch()

        let thread = app.staticTexts["Explain Swift actors"]
        app.revealSidebar(whenVisible: thread)
        let tappable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: thread)
        XCTAssertEqual(XCTWaiter().wait(for: [tappable], timeout: 10), .completed, "the thread row never became tappable")
        thread.tap()

        let text = app.replyText("Key points:")
        XCTAssertTrue(text.waitForExistence(timeout: 10), "the reply's paragraphs are selectable text views")
        XCTAssertFalse(app.buttons["reply.select-text"].exists, "no Select Text button in the footer")
        text.press(forDuration: 1.0)
        XCTAssertTrue(app.menuItems["Copy"].waitForExistence(timeout: 3), "a long press selects a word and offers Copy")
    }
}
