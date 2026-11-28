import XCTest

/// One reply with its parts (`-ARDemoParts YES`, the "Reply parts" chat): the reasoning row opens to its text, the subagent
/// card opens to its steps, and the divider of the folded history opens to the summary. The same walk as
/// ScreenshotTests.testReplyParts, with the assertions on what opens.
@MainActor
final class ReplyPartsTests: XCTestCase {
    private func openPartsChat() -> XCUIApplication {
        let app = XCUIApplication.launchedOnDemoData(extra: ["-ARDemoParts", "YES"])
        let row = app.staticTexts["Reply parts"]
        app.revealSidebar(whenVisible: row)
        XCTAssertTrue(FlowWait.until(10) { row.isHittable }, "the Reply parts chat can take a tap")
        row.tap()
        return app
    }

    /// Scrolls the chat until `element` can take a tap: down first (earlier parts), then up.
    private func bringIntoView(_ element: XCUIElement, in app: XCUIApplication) {
        var tries = 0
        while !(element.exists && element.isHittable) && tries < 6 { app.swipeDown(); tries += 1 }
        tries = 0
        while !(element.exists && element.isHittable) && tries < 12 { app.swipeUp(); tries += 1 }
        XCTAssertTrue(element.isHittable, "\(element.identifier) is reachable in the chat")
    }

    func testTheReasoningRowOpensToItsText() {
        let app = openPartsChat()
        let reasoning = app.buttons["reasoning.row"].firstMatch
        XCTAssertTrue(reasoning.waitForExistence(timeout: 10), "the reasoning row is there")
        XCTAssertTrue(reasoning.label.contains("Thought for 12s"), "it says how long the model thought: \(reasoning.label)")
        bringIntoView(reasoning, in: app)
        reasoning.tap()
        XCTAssertTrue(app.element("reasoning.text").waitForExistence(timeout: 5), "the row opens to the reasoning")
    }

    func testTheSubagentCardOpensToItsModelAndSteps() {
        let app = openPartsChat()
        let card = app.buttons["subagent.card"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10), "the subagent is one line in the reply")
        XCTAssertTrue(card.label.contains("Subagent · Research · 4 steps"), "its heading: \(card.label)")
        bringIntoView(card, in: app)
        card.tap()
        XCTAssertTrue(app.labelled(containing: "Model: ").waitForExistence(timeout: 5), "the card opens to the model it ran on")
    }

    func testTheCompactionDividerOpensToTheSummary() {
        let app = openPartsChat()
        let divider = app.buttons["compaction.divider"].firstMatch
        bringIntoView(divider, in: app)
        divider.tap()
        XCTAssertTrue(app.element("compaction.summary").waitForExistence(timeout: 5), "the divider opens to the summary")
    }

    func testAPhotoOpensTheViewerAndCloseReturnsToTheChat() {
        let app = openPartsChat()
        let photo = app.buttons["attachment.diagram.jpg"].firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 10), "the photo sits under the answer")
        bringIntoView(photo, in: app)
        photo.tap()
        XCTAssertTrue(app.element("image-viewer.image").waitForExistence(timeout: 10), "a tap on the photo opens the viewer")
        app.buttons["Close"].firstMatch.tap()
        XCTAssertTrue(app.element("image-viewer.image").waitForNonExistence(timeout: 10), "Close returns to the chat")
    }
}
