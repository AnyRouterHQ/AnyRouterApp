import XCTest

/// A short chat goes idle after a swipe. In a LazyVStack the list's size estimates never settled on a chat of a few
/// messages, so after a swipe the main thread laid the list out without end (perf 46116623560: one core busy for 30 s
/// with no query running). XCUITest waits for the app to go idle before each swipe, so a slow swipe is the failure.
@MainActor
final class ShortChatTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// The perf control's swipes (PerformanceTests.measureSwipes) on chats of three to eight messages: the loop came and
    /// went with the number of rows, and the boundary moves with the screen height.
    func testShortChatsStayIdleAfterSwipes() {
        for messages in 3...8 {
            let app = XCUIApplication()
            app.launchArguments = ["-ARDemoData", "YES", "-ARAppearance", "light", "-ARDemoLongThread", "\(messages)"]
            app.launch()
            XCTAssertTrue(app.buttons["Model"].waitForExistence(timeout: 20), "\(messages) messages: the chat opens")
            sleep(2)
            for index in 0..<8 {
                let start = Date()
                if index < 4 { app.swipeDown(velocity: .fast) } else { app.swipeUp(velocity: .fast) }
                let seconds = Date().timeIntervalSince(start)
                XCTAssertLessThan(seconds, 10, "\(messages) messages: swipe \(index + 1) waited \(Int(seconds)) s for the app to go idle")
            }
            app.terminate()
        }
    }
}
