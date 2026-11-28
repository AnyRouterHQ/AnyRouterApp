import XCTest

/// Runs against production AnyRouter with a real key from the environment (TEST_RUNNER_ANYROUTER_E2E_API_KEY, set from the
/// repo secret by e2e.yml). Skipped without a key. The key goes to the app as `-ARTestAPIKey` and is never printed or attached.
@MainActor
final class ProdE2ETests: XCTestCase {
    private func key() throws -> String {
        let value = ProcessInfo.processInfo.environment["ANYROUTER_E2E_API_KEY"] ?? ""
        try XCTSkipIf(value.isEmpty, "ANYROUTER_E2E_API_KEY is not set")
        return value
    }

    private func launch(key: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ARTestAPIKey", key]
        app.launch()
        return app
    }

    private func button(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
    }

    func testModelListLoadsAndAnAnswerStreamsIn() throws {
        let app = launch(key: try key())
        XCTAssertTrue(app.buttons["Model"].waitForExistence(timeout: 30))
        app.buttons["Model"].tap()
        let tabs = app.segmentedControls.firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 10))
        tabs.buttons["AnyRouter"].tap()
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "model-row.anyrouter/"))
        let auto = app.buttons["model-row.anyrouter/anyrouter/auto"]
        XCTAssertTrue(auto.waitForExistence(timeout: 30), "the AnyRouter model list loaded")
        XCTAssertGreaterThan(rows.count, 0)
        auto.tap()

        let input = app.element(UITestIDs.composerInput)
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.tap()
        input.typeText("What is 2+2? Answer with one number.")
        app.buttons[UITestIDs.composerAction].tap()
        let answer = app.textViews.matching(NSPredicate(format: "value CONTAINS %@ AND NOT value CONTAINS %@", "4", "What is")).firstMatch
        XCTAssertTrue(answer.waitForExistence(timeout: 90), "a streamed answer containing 4 appeared")
    }

    func testAnInvalidKeyShowsTheSignedOutState() throws {
        _ = try key()
        let app = launch(key: "sk-ar-invalid-e2e-key")
        app.revealSidebar(whenVisible: button(app, containing: "Settings"))
        button(app, containing: "Settings").tap()
        XCTAssertTrue(app.buttons["Sign in with AnyRouter"].waitForExistence(timeout: 60), "a rejected key (401) signs the user out")
    }

    func testSigningOutClearsTheKey() throws {
        let app = launch(key: try key())
        app.revealSidebar(whenVisible: button(app, containing: "Settings"))
        button(app, containing: "Settings").tap()
        let menu = app.element("account-menu")
        XCTAssertTrue(menu.waitForExistence(timeout: 30), "signed in with the injected key")
        menu.tap()
        let signOut = button(app, containing: "Sign out")
        XCTAssertTrue(signOut.waitForExistence(timeout: 5))
        signOut.tap()
        XCTAssertTrue(app.buttons["Sign in with AnyRouter"].waitForExistence(timeout: 15), "signing out shows the signed-out state")
    }
}
