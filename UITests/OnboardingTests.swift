import XCTest

/// First launch (`-ARDemoOnboarding YES`: signed out, the system model installed). The welcome page offers three ways in,
/// and both Continue with AnyRouter and Use on-device only end at the chat.
@MainActor
final class OnboardingTests: XCTestCase {
    private func launch() -> XCUIApplication {
        XCUIApplication.launchedOnDemoData(extra: ["-ARDemoOnboarding", "YES"])
    }

    func testTheWelcomePageOffersThreeWaysIn() {
        let app = launch()
        let signIn = app.buttons["onboarding.signIn"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 20), "the welcome page opens on first launch")
        XCTAssertTrue(signIn.label.contains("Continue with AnyRouter"), "signed out, the main button signs in: \(signIn.label)")
        XCTAssertTrue(app.buttons["onboarding.signUp"].exists, "a second button creates an account")
        XCTAssertTrue(app.buttons["onboarding.onDevice"].exists, "a third uses the device only")
        XCTAssertTrue(app.labelled(containing: "Welcome to AnyRouter").exists, "the page welcomes the person")
    }

    func testUseOnDeviceOnlyOpensTheChat() {
        let app = launch()
        let onDevice = app.buttons["onboarding.onDevice"]
        XCTAssertTrue(onDevice.waitForExistence(timeout: 20))
        onDevice.tap()
        XCTAssertTrue(app.element(UITestIDs.composerInput).waitForExistence(timeout: 15), "the chat opens")
        XCTAssertTrue(app.buttons["onboarding.onDevice"].waitForNonExistence(timeout: 10), "the welcome page is gone")
    }

    func testContinueWithAnyRouterSignsInAndOpensTheChat() {
        let app = launch()
        let signIn = app.buttons["onboarding.signIn"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 20))
        signIn.tap()
        XCTAssertTrue(app.element(UITestIDs.composerInput).waitForExistence(timeout: 15), "the chat opens")
        XCTAssertTrue(app.buttons["onboarding.signIn"].waitForNonExistence(timeout: 10), "the welcome page is gone")
    }
}
