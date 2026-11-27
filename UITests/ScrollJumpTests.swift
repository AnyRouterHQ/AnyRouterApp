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
