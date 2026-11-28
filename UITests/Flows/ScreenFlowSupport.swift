import XCTest

/// Polls a condition on the main thread. For states that have no element to wait for.
@MainActor
enum FlowWait {
    static func until(_ timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if condition() { return true }
            usleep(200_000)
        }
        return condition()
    }
}

/// Moves the screen-by-screen flow tests share. Settings opens through the sidebar's gear, and a page opens by its row.
extension XCUIApplication {
    /// The first element of any type whose label contains `text`. A container with its own identifier can hide the
    /// labels of its children from a typed query, so this one does not care about the type.
    func labelled(containing text: String) -> XCUIElement {
        descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
    }

    /// An element's label and value as one string, for a check on what it says.
    func words(of element: XCUIElement) -> String {
        element.label + " " + String(describing: element.value ?? "")
    }

    /// Opens Settings from the sidebar's gear and waits for its navigation bar.
    func showSettings() {
        let gear = buttons["sidebar.settings"]
        revealSidebar(whenVisible: gear)
        gear.tap()
        XCTAssertTrue(navigationBars["Settings"].waitForExistence(timeout: 10), "Settings opened")
    }

    /// Drags the page under `bar` up until `element` can take a tap. A swipe at the app's centre lands beside a form
    /// sheet on iPad, and a lazy list has no row in the tree until it has scrolled to it.
    func scrollPage(under bar: XCUIElement, until element: XCUIElement) {
        var tries = 0
        while !(element.exists && element.isHittable) && tries < 12 {
            let start = bar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).withOffset(CGVector(dx: 0, dy: 450))
            start.press(forDuration: 0.01, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -300)))
            tries += 1
        }
    }

    /// A row of a list whose label starts with `title`. Rows with a second line carry it in their label.
    func listRow(_ title: String) -> XCUIElement {
        buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
    }

    /// Opens Settings and pushes the page whose row is called `title`.
    func showSettingsPage(_ title: String) {
        showSettings()
        let row = listRow(title)
        scrollPage(under: navigationBars["Settings"], until: row)
        XCTAssertTrue(row.isHittable, "the \(title) row is reachable in Settings")
        row.tap()
        XCTAssertTrue(navigationBars[title].waitForExistence(timeout: 10), "the \(title) page opened")
    }

    /// Goes back from the page called `title` and waits for the page called `parent`.
    func goBack(from title: String, to parent: String) {
        navigationBars[title].buttons["BackButton"].tap()
        XCTAssertTrue(navigationBars[parent].waitForExistence(timeout: 5), "back on \(parent)")
    }

    /// Taps a switch at its trailing edge (a tap at the centre lands on the label) and reports whether its value changed.
    func flipSwitch(_ toggle: XCUIElement) -> Bool {
        let before = toggle.value as? String
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        return FlowWait.until(5) { (toggle.value as? String) != before }
    }
}
