import XCTest

/// "Remember that" in a message: the reply leads with a "Memory updated" row, and its Undo takes the item back.
@MainActor
final class MemoryRowTests: XCTestCase {
    func testRememberThatShowsTheRowAndUndoTakesItBack() {
        let app = XCUIApplication.launchedOnDemoData(extra: ["-ARDemoStream", "20@20"])
        let input = app.element(UITestIDs.composerInput)
        XCTAssertTrue(input.waitForExistence(timeout: 15))
        input.tap()
        input.typeText("Remember that I am vegetarian")
        app.element(UITestIDs.composerAction).tap()

        let row = app.buttons.matching(identifier: "memory.update").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20), "the reply shows what was saved")
        XCTAssertTrue(row.label.contains("Memory updated"), row.label)
        row.tap()
        let undo = app.buttons["memory.undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5), "the open row offers Undo")
        XCTAssertTrue(app.buttons["memory.edit"].exists, "and Edit")
        undo.tap()

        let undone = app.buttons.matching(identifier: "memory.update").matching(NSPredicate(format: "label CONTAINS %@", "undone")).firstMatch
        XCTAssertTrue(undone.waitForExistence(timeout: 5), "the row says the save was undone")
        XCTAssertFalse(app.buttons["memory.undo"].exists, "an undone save has nothing left to undo")
    }
}
