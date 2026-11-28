import XCTest

/// The jump-to-latest button: absent while the list is at the bottom, present after scrolling up, gone again after the tap
/// and after scrolling back down by hand.
/// Uses the 200-message demo thread, which opens at launch.
@MainActor
final class ScrollJumpTests: XCTestCase {
    /// A fast drag inside the window, right of the iPad sidebar column. Not `chat.content.swipe…`: that container is as
    /// tall as the whole thread, so its center is far off screen and the swipe did not scroll (verify-ui 46067163702).
    private func swipe(_ app: XCUIApplication, towardsTheTop: Bool) {
        let window = app.windows.firstMatch
        let upper = window.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.3))
        let lower = window.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.75))
        let (from, to) = towardsTheTop ? (upper, lower) : (lower, upper)
        from.press(forDuration: 0.01, thenDragTo: to, withVelocity: .fast, thenHoldForDuration: 0)
    }

    func testJumpButtonAppearsOnlyAwayFromTheBottom() {
        let app = XCUIApplication()
        app.launchArguments = ["-ARDemoData", "YES", "-ARDemoLongThread", "200"]
        app.launch()
        let content = app.descendants(matching: .any)["chat.content"]
        XCTAssertTrue(content.waitForExistence(timeout: 20))
        let jump = app.buttons["jump-to-latest"]
        sleep(1)
        XCTAssertFalse(jump.exists, "at the bottom the button must not show")

        for _ in 0..<3 { swipe(app, towardsTheTop: true) }
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
        sleep(1)
        evidence(app, "anchor-1-after-send")
        XCTAssertTrue(app.buttons["Voice input"].waitForExistence(timeout: 30), "the reply finished")
        sleep(1)
        evidence(app, "anchor-2-reply-ended")

        // The bubble is not a plain static text (verify-ui 46031167020): match any element that carries the words.
        // A selectable text view carries its words as the value, not the label.
        let question = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "anchor check", "anchor check")).firstMatch
        // On failure, name what the tree holds instead (verify-ui 46083142998 found no element with these words).
        let tree = app.debugDescription.split(separator: "\n").filter { $0.contains("anchor") || $0.contains("Question 100") }
        XCTAssertTrue(question.exists, "the sent question is on screen; tree lines: \(tree.prefix(4).joined(separator: " | "))")
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
        let content = app.descendants(matching: .any)["chat.content"]
        XCTAssertTrue(content.waitForExistence(timeout: 20))
        let jump = app.buttons["jump-to-latest"]
        // As in the test above: let the thread settle at its end before the first swipe (it failed here without it).
        sleep(1)
        for _ in 0..<3 { swipe(app, towardsTheTop: true) }
        XCTAssertTrue(jump.waitForExistence(timeout: 5), "scrolled up, the button should show")

        for _ in 0..<8 { swipe(app, towardsTheTop: false) }
        XCTAssertTrue(jump.waitForNonExistence(timeout: 5), "at the bottom again the button must go away without a tap")
    }

    /// A PNG in the verify-ui evidence (SCREENSHOT_DIR/scrolljump), so a failing anchor run shows where the question was.
    private func evidence(_ app: XCUIApplication, _ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"], !dir.isEmpty else { return }
        let folder = URL(fileURLWithPath: dir).appendingPathComponent("scrolljump")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? app.screenshot().pngRepresentation.write(to: folder.appendingPathComponent("\(name).png"))
    }
}
