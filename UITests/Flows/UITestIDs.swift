import XCTest

/// Accessibility identifiers the flow tests rely on, in one place. Add a constant here instead of typing a string in a test.
/// Never query by visible text for anything that is localized.
enum UITestIDs {
    static let composerInput = "composer.input"
    static let composerAction = "composer.action"
    static let homeSubtitle = "home.subtitle"
    static let mentionPanel = "mention.panel"
    static let mentionPrefix = "mention."
    static let mentionChipPrefix = "mention.chip."
    static let sidebarHeader = "sidebar.header"
    static let hubStorage = "hub.storage"
}

extension XCUIApplication {
    /// Any element with this identifier, whatever its type.
    func element(_ id: String) -> XCUIElement {
        descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /// Launches on demo data, with extra launch arguments.
    static func launchedOnDemoData(appearance: String? = nil, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        var arguments = ["-ARDemoData", "YES"]
        if let appearance { arguments += ["-ARAppearance", appearance] }
        app.launchArguments = arguments + extra
        app.launch()
        return app
    }

    func waitForKeyboard(present: Bool, timeout: TimeInterval = 5) -> Bool {
        let predicate = NSPredicate(format: "count \(present ? ">" : "==") 0")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: keyboards)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}
