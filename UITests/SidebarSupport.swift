import XCTest

extension XCUIApplication {
    /// The system's sidebar button in a regular-width window (its label changes with the state, so match the word).
    var sidebarToggle: XCUIElement {
        buttons.matching(NSPredicate(format: "label CONTAINS[c] 'sidebar'")).firstMatch
    }

    /// Whether the thread list is on screen. iPhone: the chat slides right by the drawer width, so the Menu button sits in
    /// the right half; "Close sidebar" and the drawer's own views stay in the tree while it is closed, so they prove nothing
    /// (a run showed them "open" over a chat at full width). iPad: the column's compose button is on screen.
    var sidebarIsOpen: Bool {
        let window = windows.firstMatch.frame
        let menu = buttons["Menu"]
        if menu.exists { return menu.frame.minX > window.width / 2 }
        let compose = buttons["sidebar.compose"]
        guard compose.exists else { return false }
        let frame = compose.frame
        return !frame.isEmpty && frame.midX > window.minX && frame.midX < window.maxX
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
