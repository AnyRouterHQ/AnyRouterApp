import XCTest

/// A reply that fails shows why in the chat, stays after a relaunch, and Retry replaces it. Demo data with an on-disk store.
@MainActor
final class ReplyFailureTests: XCTestCase {
    private func launch(store: String, failing: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ARDemoData", "YES", "-ARDemoStore", store] + (failing ? ["-ARDemoFail", "rateLimited"] : [])
        app.launch()
        return app
    }

    func testAFailedReplyStaysAfterARelaunchAndRetryReplacesIt() {
        let question = "Plan a weekend in Porto"
        var app = launch(store: "fresh", failing: true)
        let input = app.element(UITestIDs.composerInput)
        XCTAssertTrue(input.waitForExistence(timeout: 15))
        input.tap()
        input.typeText(question)
        app.buttons["Send"].tap()

        let failure = app.staticTexts["reply-failure"]
        XCTAssertTrue(failure.waitForExistence(timeout: 10), "the failed reply shows in the chat")
        XCTAssertTrue(failure.label.contains("busy"), "one plain sentence, not the raw error: \(failure.label)")
        XCTAssertTrue(app.buttons["reply-failure.retry"].exists)
        let detail = app.descendants(matching: .any)["reply-failure.detail"]
        XCTAssertFalse(detail.exists, "the raw text waits behind the row")
        app.buttons["Details"].firstMatch.tap()
        XCTAssertTrue(detail.waitForExistence(timeout: 5))
        XCTAssertTrue(detail.label.contains("Rate limit exceeded"), "the raw text: \(detail.label)")
        XCTAssertTrue(app.buttons["reply-failure.copy"].exists)
        app.terminate()

        // The engine works again after the relaunch, so Retry gets an answer.
        app = launch(store: "keep", failing: false)
        let row = app.collectionViews.staticTexts[question]
        app.revealSidebar(whenVisible: row)
        row.tap()
        XCTAssertTrue(app.staticTexts["reply-failure"].waitForExistence(timeout: 10), "the failure is still there after a relaunch")
        app.buttons["reply-failure.retry"].tap()
        // Reply text is a selectable text view, found by its value (ReplyTextSupport in JourneySupport).
        XCTAssertTrue(app.replyText("This is a demo reply.").waitForExistence(timeout: 10), "Retry got an answer")
        XCTAssertFalse(app.staticTexts["reply-failure"].exists, "Retry replaced the failed reply")
        XCTAssertEqual(app.replyTexts("This is a demo reply.").count, 1, "one reply, not a second one under the failure")
    }
}
