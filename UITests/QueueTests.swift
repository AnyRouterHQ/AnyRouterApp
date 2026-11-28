import XCTest

/// Queue mode: messages sent while a reply streams wait above the composer and go out one by one (demo data, slow stream).
/// Each demo reply streams for 50 s: at 7.5 s (verify-ui 46091124302) the first reply ended while the test still typed, so
/// the queue had already gone out when it was checked.
@MainActor
final class QueueTests: XCTestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication.launchedOnDemoData(extra: ["-ARDemoStream", "1000@20"])
        XCTAssertTrue(app.element(UITestIDs.composerInput).waitForExistence(timeout: 15))
        return app
    }

    private func type(_ text: String, in app: XCUIApplication) {
        let input = app.element(UITestIDs.composerInput)
        input.tap()
        input.typeText(text)
        app.element(UITestIDs.composerAction).tap()
    }

    private func message(_ text: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    func testMessagesSentWhileAReplyStreamsGoOutInOrder() {
        let app = launch()
        type("first", in: app)
        XCTAssertTrue(app.buttons["Stop"].waitForExistence(timeout: 10), "the first reply is streaming")
        type("second", in: app)
        type("third", in: app)
        XCTAssertEqual(app.element("chat.queue.row").waitForExistence(timeout: 5), true, "queued messages show above the composer")
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "chat.queue.row").count, 2)
        XCTAssertTrue(app.buttons["composer.stop"].exists || app.buttons["Stop"].exists, "stop stays reachable")

        let second = message("second", in: app)
        let third = message("third", in: app)
        XCTAssertTrue(app.element("chat.queue.row").waitForNonExistence(timeout: 200), "both queued messages were sent")
        XCTAssertTrue(second.waitForExistence(timeout: 10))
        XCTAssertTrue(third.waitForExistence(timeout: 10))
        XCTAssertLessThan(second.frame.minY, third.frame.minY, "in the order they were typed")
    }

    func testStoppingHoldsTheQueueUntilSendQueued() {
        let app = launch()
        type("first", in: app)
        XCTAssertTrue(app.buttons["Stop"].waitForExistence(timeout: 10))
        type("second", in: app)
        XCTAssertTrue(app.element("chat.queue.row").waitForExistence(timeout: 5))
        app.buttons["Stop"].tap()
        let resume = app.buttons["chat.queue.resume"]
        XCTAssertTrue(resume.waitForExistence(timeout: 10), "a stopped reply holds the queue")
        XCTAssertTrue(resume.label.contains("(1)"), "the button says how many wait")
        resume.tap()
        XCTAssertTrue(app.element("chat.queue.row").waitForNonExistence(timeout: 10), "Send queued sends it")
    }

    func testRemovingAQueuedMessage() {
        let app = launch()
        type("first", in: app)
        XCTAssertTrue(app.buttons["Stop"].waitForExistence(timeout: 10))
        type("second", in: app)
        XCTAssertTrue(app.element("chat.queue.row").waitForExistence(timeout: 5))
        app.buttons["chat.queue.remove"].tap()
        XCTAssertTrue(app.element("chat.queue.row").waitForNonExistence(timeout: 5))
    }
}
