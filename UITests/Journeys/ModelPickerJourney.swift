import XCTest

/// Model picker: open from the pill, choose a cloud model in the AnyRouter tab, then switch models in the middle of a conversation.
@MainActor
final class ModelPickerJourney: JourneyCase {
    private func choose(id: String, shownAs name: String, search: String, _ app: XCUIApplication) {
        app.buttons["Model"].tap()
        let tabs = app.segmentedControls.firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 5), "picker tabs")
        tabs.buttons["AnyRouter"].tap()
        let field = app.searchFields["Search models"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(search)
        let row = app.buttons["model-row.\(id)"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "\(name) row")
        step("picker-anyrouter-filtered-\(search.lowercased())")
        row.tap()
        let pill = app.buttons["Model"]
        XCTAssertTrue(pill.waitForExistence(timeout: 5))
        XCTAssertEqual(pill.value as? String, name, "pill shows the chosen model")
    }

    func testChooseModelAndSwitchMidConversation() {
        runPasses { app, _ in
            let pill = app.buttons["Model"]
            XCTAssertTrue(pill.waitForExistence(timeout: 15))
            XCTAssertEqual(pill.value as? String, "AnyRouter", "signed in, the router picks the model")
            pill.tap()
            XCTAssertTrue(app.segmentedControls.firstMatch.waitForExistence(timeout: 5))
            step("picker-open")
            app.segmentedControls.firstMatch.buttons["Local"].tap()
            XCTAssertTrue(app.buttons["model-row.apple/foundation"].waitForExistence(timeout: 5), "Local tab lists Apple Intelligence")
            step("picker-local-tab")
            audit(app, "picker-local")
            app.segmentedControls.firstMatch.buttons["AnyRouter"].tap()
            sleep(1)
            step("picker-anyrouter-tab")
            audit(app, "picker-anyrouter")
            app.buttons["Close"].tap()

            choose(id: "anyrouter/anthropic/claude-sonnet-4-6", shownAs: "Claude Sonnet 4.6", search: "sonnet", app)
            step("chose-claude")

            let input = composer(app)
            input.tap()
            input.typeText("First question")
            app.buttons["Send"].tap()
            XCTAssertTrue(app.replyText("This is a demo reply.").waitForExistence(timeout: 10))
            step("first-reply")

            choose(id: "anyrouter/google/gemini-2.5-pro", shownAs: "Gemini 2.5 Pro", search: "gemini", app)
            let again = composer(app)
            again.tap()
            again.typeText("Second question")
            app.buttons["Send"].tap()
            let replies = app.replyTexts("This is a demo reply.")
            expectation(for: NSPredicate(format: "count == 2"), evaluatedWith: replies)
            waitForExpectations(timeout: 10)
            XCTAssertTrue(app.descendants(matching: .any)["switch-note"].waitForExistence(timeout: 5), "the reply notes the model switch")
            step("second-reply-after-switch")
        }
    }
}
