import XCTest

/// The account card at the top of Settings, signed out (`-ARDemoSignedOut YES`): it offers Sign in and Create account,
/// signing in swaps it for the signed-in card with its options menu, and Sign out brings the prompt back.
@MainActor
final class AccountCardTests: XCTestCase {
    func testSigningInAndOutSwapsTheCard() {
        let app = XCUIApplication.launchedOnDemoData(extra: ["-ARDemoSignedOut", "YES"])
        app.showSettings()
        let signIn = app.buttons["Sign in with AnyRouter"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 10), "signed out, the card offers Sign in")
        XCTAssertTrue(app.buttons["Create account"].exists, "and Create account")
        XCTAssertFalse(app.buttons["account-menu"].exists, "there is no account menu yet")

        signIn.tap()
        let menu = app.buttons["account-menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10), "signed in, the card has its options menu")
        XCTAssertTrue(signIn.waitForNonExistence(timeout: 5), "the sign-in prompt is gone")

        menu.tap()
        let signOut = app.buttons["Sign out"]
        XCTAssertTrue(signOut.waitForExistence(timeout: 5), "the menu offers Sign out")
        signOut.tap()
        XCTAssertTrue(app.buttons["Sign in with AnyRouter"].waitForExistence(timeout: 10), "signing out brings the prompt back")
    }
}
