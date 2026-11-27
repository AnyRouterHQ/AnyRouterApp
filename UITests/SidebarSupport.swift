import XCTest

extension XCUIApplication {
    /// The system's sidebar button in a regular-width window (its label changes with the state, so match the word).
    var sidebarToggle: XCUIElement {
        buttons.matching(NSPredicate(format: "label CONTAINS[c] 'sidebar'")).firstMatch
    }

    /// Whether the thread list can be used. iPhone: the drawer sits under the chat and its views stay in the tree
    /// while it is closed (not hittable), so the sign is the "Close sidebar" scrim that exists only while it is open.
    /// iPad: the column's compose button is on screen.
    var sidebarIsOpen: Bool {
        if buttons["Close sidebar"].exists { return true }
        if buttons["Menu"].exists { return false }
        let compose = buttons["sidebar.compose"]
        let frame = compose.frame
        let window = windows.firstMatch.frame
        return compose.exists && !frame.isEmpty && frame.midX > window.minX && frame.midX < window.maxX
    }

    /// Brings the thread list on screen. iPhone: the drawer behind the Menu button. iPad: a column that is open in
    /// landscape and tucked away in portrait, so it may need the toolbar toggle. `visible` is something only the sidebar
    /// shows; it is awaited once the sidebar reports open.
    func revealSidebar(whenVisible visible: XCUIElement) {
        if sidebarIsOpen, visible.exists { return }
        if !sidebarIsOpen {
            if buttons["Menu"].waitForExistence(timeout: 3) {
                buttons["Menu"].tap()
            } else {
                XCTAssertTrue(sidebarToggle.waitForExistence(timeout: 10), "no way to open the sidebar")
                sidebarToggle.tap()
            }
        }
        let end = Date().addingTimeInterval(5)
        while Date() < end, !sidebarIsOpen { usleep(200_000) }
        XCTAssertTrue(sidebarIsOpen, "the sidebar did not open")
        XCTAssertTrue(visible.waitForExistence(timeout: 5), "the sidebar did not show what the test needs")
        sleep(1)
    }
}
