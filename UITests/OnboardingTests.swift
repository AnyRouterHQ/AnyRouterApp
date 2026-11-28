import XCTest

/// First launch (`-ARDemoOnboarding YES`: signed out, the system model installed). The welcome page offers two ways in,
/// and both Log in to AnyRouter and Use local models only end at the chat.
@MainActor
final class OnboardingTests: XCTestCase {
    private func launch() -> XCUIApplication {
        XCUIApplication.launchedOnDemoData(extra: ["-ARDemoOnboarding", "YES"])
    }

    func testTheWelcomePageOffersTwoWaysIn() {
        let app = launch()
        let signIn = app.buttons["onboarding.signIn"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 20), "the welcome page opens on first launch")
        XCTAssertTrue(signIn.label.contains("Log in to AnyRouter"), "signed out, the main button signs in: \(signIn.label)")
        XCTAssertTrue(app.buttons["onboarding.onDevice"].exists, "a second uses local models only")
        XCTAssertTrue(app.labelled(containing: "AnyRouter").exists, "the page names the app")
    }

    func testUseOnDeviceOnlyOpensTheChat() {
        let app = launch()
        let onDevice = app.buttons["onboarding.onDevice"]
        XCTAssertTrue(onDevice.waitForExistence(timeout: 20))
        onDevice.tap()
        XCTAssertTrue(app.element(UITestIDs.composerInput).waitForExistence(timeout: 15), "the chat opens")
        XCTAssertTrue(app.buttons["onboarding.onDevice"].waitForNonExistence(timeout: 10), "the welcome page is gone")
    }

    func testLogInToAnyRouterSignsInAndOpensTheChat() {
        let app = launch()
        let signIn = app.buttons["onboarding.signIn"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 20))
        signIn.tap()
        XCTAssertTrue(app.element(UITestIDs.composerInput).waitForExistence(timeout: 15), "the chat opens")
        XCTAssertTrue(app.buttons["onboarding.signIn"].waitForNonExistence(timeout: 10), "the welcome page is gone")
    }
}
