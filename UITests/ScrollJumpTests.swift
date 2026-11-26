import XCTest

/// The jump-to-latest button: absent while the list is at the bottom, present after scrolling up, gone again after the tap.
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
}
