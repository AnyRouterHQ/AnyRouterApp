import XCTest

extension XCUIApplication {
    /// The system's sidebar button in a regular-width window (its label changes with the state, so match the word).
    var sidebarToggle: XCUIElement {
        buttons.matching(NSPredicate(format: "label CONTAINS[c] 'sidebar'")).firstMatch
    }

    /// By frame: `isHittable` throws "Activation point invalid" for the closed drawer's views, which sit off screen.
    func isOnScreen(_ element: XCUIElement) -> Bool {
        guard element.exists else { return false }
        let frame = element.frame
        let window = windows.firstMatch.frame
        return !frame.isEmpty && frame.midX > window.minX && frame.midX < window.maxX
            && frame.midY > window.minY && frame.midY < window.maxY
    }

    /// Brings the thread list on screen. iPhone: the drawer behind the Menu button. iPad: a column that is open in
    /// landscape and tucked away in portrait, so it may need the toolbar toggle. `visible` is something only the sidebar shows.
    func revealSidebar(whenVisible visible: XCUIElement) {
        // The drawer keeps its views in the tree while closed, so "exists" is not "on screen".
        if visible.waitForExistence(timeout: 2), isOnScreen(visible) { return }
        if buttons["Menu"].waitForExistence(timeout: 3) {
            buttons["Menu"].tap()
        } else {
            XCTAssertTrue(sidebarToggle.waitForExistence(timeout: 10), "no way to open the sidebar")
            sidebarToggle.tap()
        }
        let end = Date().addingTimeInterval(5)
        while Date() < end, !isOnScreen(visible) { usleep(200_000) }
        XCTAssertTrue(isOnScreen(visible), "the sidebar did not open")
        sleep(1)
    }
}
