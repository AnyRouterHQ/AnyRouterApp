import XCTest

/// A run that waits for a tool approval survives the app being killed (agent design 1.3): after a relaunch the card is back
/// on its call, and Allow or Don't allow continues the run. Demo data with an on-disk store; `-ARDemoApproval YES` makes the
/// demo cloud engine ask for one external tool in its first round and answer with the tool's result in the second.
@MainActor
final class ApprovalResumeTests: XCTestCase {
    private let question = "Send the note to Ada"
    private let card = "tool-approval.inline"

    private func launch(store: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ARDemoData", "YES", "-ARDemoStore", store, "-ARDemoApproval", "YES"]
        app.launch()
        return app
    }

    /// Asks the question, waits for the approval card, kills the app, and opens the chat again after a relaunch.
    private func relaunchedOnTheWaitingCard() -> XCUIApplication {
        var app = launch(store: "fresh")
        let input = app.element(UITestIDs.composerInput)
        XCTAssertTrue(input.waitForExistence(timeout: 15))
        input.tap()
        input.typeText(question)
        app.buttons["Send"].tap()
        XCTAssertTrue(app.element(card).waitForExistence(timeout: 15), "the run waits for approval")
        app.terminate()

        app = launch(store: "keep")
        let row = app.collectionViews.staticTexts[question]
        app.revealSidebar(whenVisible: row)
        row.tap()
        XCTAssertTrue(app.element(card).waitForExistence(timeout: 20), "the card is back after the relaunch")
        return app
    }

    /// The reply text view that holds `text`, found by its value (reply text is a selectable text view).
    private func reply(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.textViews.matching(NSPredicate(format: "value CONTAINS %@", text)).firstMatch
    }

    func testAllowAfterARelaunchContinuesTheRunWithTheToolResult() {
        let app = relaunchedOnTheWaitingCard()
        app.element("\(card).allow-once").tap()
        XCTAssertTrue(reply(app, containing: "Result: The note was sent.").waitForExistence(timeout: 15), "the tool result reached the reply")
        XCTAssertFalse(app.element(card).exists, "the card is gone once answered")
    }

    func testDenyAfterARelaunchContinuesTheRunAndTheReplySaysItWasNotAllowed() {
        let app = relaunchedOnTheWaitingCard()
        app.element("\(card).deny").tap()
        XCTAssertTrue(
            reply(app, containing: "Result: The user did not allow this tool call.").waitForExistence(timeout: 15),
            "the run went on and the reply says the call was not allowed")
        XCTAssertFalse(app.element(card).exists, "the card is gone once answered")
    }
}
