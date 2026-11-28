import XCTest

/// Unit X1: a reply from the model on this device that could not answer offers "Ask a cloud model"; a notice names
/// AnyRouter before the chat leaves the device, and the question then goes to a cloud model.
@MainActor
final class AskCloudTests: XCTestCase {
    func testATooLongDeviceReplyOffersACloudModelBehindANotice() {
        let app = XCUIApplication()
        // The 4-message demo thread opens on Apple's model; every reply fails as too long for the window.
        app.launchArguments = ["-ARDemoData", "YES", "-ARDemoLongThread", "4", "-ARDemoFail", "contextTooLong"]
        app.launch()
        let input = app.element(UITestIDs.composerInput)
        XCTAssertTrue(input.waitForExistence(timeout: 20))
        input.tap()
        input.typeText("One more question")
        app.buttons["Send"].tap()

        let ask = app.buttons["reply-failure.askCloudModel"]
        XCTAssertTrue(ask.waitForExistence(timeout: 30), "a device reply that did not fit offers a cloud model")
        XCTAssertTrue(app.buttons["reply-failure.shortenChat"].exists, "Shorten chat stays the first fix")
        ask.tap()

        let confirm = app.buttons["reply.askCloud.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "a notice comes first")
        let notice = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "AnyRouter")).firstMatch
        XCTAssertTrue(notice.exists, "the notice says where the chat goes")
        confirm.tap()

        // The cloud reply fails too in this demo, but it is not a device reply, so it offers no cloud model.
        XCTAssertTrue(ask.waitForNonExistence(timeout: 30), "the question went to a cloud model")
        XCTAssertTrue(app.buttons["reply-failure"].waitForExistence(timeout: 10))
    }
}
