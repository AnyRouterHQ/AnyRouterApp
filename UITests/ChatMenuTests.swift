import XCTest

/// The chat's "..." menu beyond Rename (ChatTitleTests): the memory switch for this chat flips, and Compact conversation is
/// there. A 20-message demo chat opens at launch.
@MainActor
final class ChatMenuTests: XCTestCase {
    func testTheMemorySwitchOfThisChatFlips() {
        let app = XCUIApplication.launchedOnDemoData(extra: ["-ARDemoLongThread", "20"])
        let more = app.buttons["chat.more"]
        XCTAssertTrue(more.waitForExistence(timeout: 20), "the chat's menu is in the bar")
        more.tap()
        let memory = app.element("chat.memoryOff")
        XCTAssertTrue(memory.waitForExistence(timeout: 5), "the menu has the memory switch for this chat")
        XCTAssertTrue(app.element("chat.compact").exists, "and Compact conversation")
        let before = app.words(of: memory)
        memory.tap()

        more.tap()
        let after = app.element("chat.memoryOff")
        XCTAssertTrue(after.waitForExistence(timeout: 5), "the menu opens again")
        XCTAssertTrue(FlowWait.until(5) { app.words(of: after) != before }, "the switch changed from: \(before)")
    }
}
