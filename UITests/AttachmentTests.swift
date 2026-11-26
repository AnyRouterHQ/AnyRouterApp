import XCTest

/// A text file staged by demo mode shows as a chip under the composer, and Send is enabled without any typing.
@MainActor
final class AttachmentTests: XCTestCase {
    func testAttachedTextFileShowsAChipAndEnablesSend() {
        let app = XCUIApplication()
        app.launchArguments = ["-ARDemoData", "YES", "-ARDemoAttachFile", "YES"]
        app.launch()

        let chip = app.descendants(matching: .any)["attachment-chip.notes.txt"]
        XCTAssertTrue(chip.waitForExistence(timeout: 20), "the notes.txt chip appears above the field")
        XCTAssertTrue(app.buttons["Remove notes.txt"].exists)
        XCTAssertTrue(app.buttons["Send"].isEnabled, "an attachment alone can be sent")

        app.buttons["Remove notes.txt"].tap()
        XCTAssertFalse(chip.waitForExistence(timeout: 2), "removing the chip drops the file")
    }
}
