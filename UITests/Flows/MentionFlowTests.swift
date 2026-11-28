import XCTest

/// The composer "@" panel: plugin rows, filtering, picking keeps the keyboard up, chips can be removed.
@MainActor
final class MentionFlowTests: XCTestCase {
    private func mentionRows(_ app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND NOT identifier BEGINSWITH %@",
                                         UITestIDs.mentionPrefix, UITestIDs.mentionChipPrefix))
    }

    private func focusedComposer(_ app: XCUIApplication) -> XCUIElement {
        let input = app.element(UITestIDs.composerInput)
        XCTAssertTrue(input.waitForExistence(timeout: 15))
        input.tap()
        XCTAssertTrue(app.waitForKeyboard(present: true))
        return input
    }

    func testTypingAtOpensThePluginListAndAPickBecomesAChip() {
        let app = XCUIApplication.launchedOnDemoData()
        let input = focusedComposer(app)
        input.typeText("@")
        XCTAssertTrue(app.element(UITestIDs.mentionPanel).waitForExistence(timeout: 5), "the @ panel opens")
        XCTAssertGreaterThan(mentionRows(app).count, 0, "the panel lists plugins")

        input.typeText("ex")
        let exa = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS[c] %@", UITestIDs.mentionPrefix, "Exa")).firstMatch
        XCTAssertTrue(exa.waitForExistence(timeout: 5), "typing ex narrows the list to Exa")
        exa.tap()

        let chip = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", UITestIDs.mentionChipPrefix)).firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 5), "the pick becomes a chip above the field")
        XCTAssertTrue(app.keyboards.count > 0, "the keyboard stays up after a pick")
        XCTAssertFalse(app.element(UITestIDs.mentionPanel).exists, "the panel closes after a pick")

        chip.tap()
        XCTAssertTrue(chip.waitForNonExistence(timeout: 5), "tapping the chip removes it")
    }

    func testAnEmailAddressDoesNotOpenThePanel() {
        let app = XCUIApplication.launchedOnDemoData()
        let input = focusedComposer(app)
        input.typeText("me@example.com")
        XCTAssertFalse(app.element(UITestIDs.mentionPanel).waitForExistence(timeout: 2), "an @ inside a word is not a mention")
    }
}
