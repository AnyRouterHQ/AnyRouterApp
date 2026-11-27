import XCTest

/// The jump-to-latest button: absent while the list is at the bottom, present after scrolling up, gone again after the tap
/// and after scrolling back down by hand.
/// Uses the 200-message demo thread, which opens at launch.
@MainActor
final class ScrollJumpTests: XCTestCase {
    func testJumpButtonAppearsOnlyAwayFromTheBottom() {
        let app = XCUIApplication()
        app.launchArguments = ["-ARDemoData", "YES", "-ARDemoLongThread", "200"]
        app.launch()
        let content = app.descendants(matching: .any)["chat.content"]
        XCTAssertTrue(content.waitForExistence(timeout: 20))
        let jump = app.buttons["jump-to-latest"]
        sleep(1)
        XCTAssertFalse(jump.exists, "at the bottom the button must not show")

        for _ in 0..<3 { app.swipeDown(velocity: .fast) }
        XCTAssertTrue(jump.waitForExistence(timeout: 5), "scrolled up, the button should show")

        jump.tap()
        XCTAssertTrue(jump.waitForNonExistence(timeout: 5), "back at the bottom the button should go away")
    }

    /// Decision D27: a sent question settles at the top of the view and stays there when its reply ends, in a long thread
    /// where the end of the list would otherwise be far below it.
    func testASentQuestionSettlesAtTheTopAndStaysWhenTheReplyEnds() {
        let app = XCUIApplication()
        app.launchArguments = ["-ARDemoData", "YES", "-ARDemoLongThread", "200"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["chat.content"].waitForExistence(timeout: 20))
        let input = app.element(UITestIDs.composerInput)
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.tap()
        input.typeText("anchor check")
        app.buttons["Send"].tap()
        XCTAssertTrue(app.buttons["Voice input"].waitForExistence(timeout: 30), "the reply finished")
        sleep(1)

        let question = app.staticTexts["anchor check"].firstMatch
        XCTAssertTrue(question.exists)
        let window = app.windows.firstMatch.frame
        XCTAssertLessThan(question.frame.minY, window.height * 0.35, "the question sits near the top after the reply ended")
        XCTAssertGreaterThan(question.frame.minY, 0, "and is on screen, not scrolled past")
    }

    /// The operator's report: scrolled back to the end by hand, the arrow stayed. The list ends at the bottom, so extra
    /// swipes up only bounce there.
    func testJumpButtonGoesAwayWhenScrolledBackToTheBottomByHand() {
        let app = XCUIApplication()
        app.launchArguments = ["-ARDemoData", "YES", "-ARDemoLongThread", "200"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["chat.content"].waitForExistence(timeout: 20))
        let jump = app.buttons["jump-to-latest"]
        for _ in 0..<3 { app.swipeDown(velocity: .fast) }
        XCTAssertTrue(jump.waitForExistence(timeout: 5), "scrolled up, the button should show")

        for _ in 0..<8 { app.swipeUp(velocity: .fast) }
        XCTAssertTrue(jump.waitForNonExistence(timeout: 5), "at the bottom again the button must go away without a tap")
    }
}
