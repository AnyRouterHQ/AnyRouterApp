import XCTest

extension XCUIApplication {
    /// The system's sidebar button in a regular-width window (its label changes with the state, so match the word).
    var sidebarToggle: XCUIElement {
        buttons.matching(NSPredicate(format: "label CONTAINS[c] 'sidebar'")).firstMatch
    }

    /// Brings the thread list on screen. iPhone: the drawer behind the Menu button. iPad: a column that is open in
    /// landscape and tucked away in portrait, so it may need the toolbar toggle. `visible` is something only the sidebar shows.
    func revealSidebar(whenVisible visible: XCUIElement) {
        // The drawer keeps its views in the tree while closed, so "exists" is not "on screen".
        if visible.waitForExistence(timeout: 2), visible.isHittable { return }
        if buttons["Menu"].waitForExistence(timeout: 3) {
            buttons["Menu"].tap()
        } else {
            XCTAssertTrue(sidebarToggle.waitForExistence(timeout: 10), "no way to open the sidebar")
            sidebarToggle.tap()
        }
        let onScreen = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND isHittable == true"), object: visible)
        XCTAssertEqual(XCTWaiter().wait(for: [onScreen], timeout: 5), .completed, "the sidebar did not open")
        sleep(1)
    }
}
