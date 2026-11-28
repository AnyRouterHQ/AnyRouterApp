import XCTest

/// Manage models (hub): installed and downloading models, sort and filter menus, search narrows the list.
@MainActor
final class HubJourney: JourneyCase {
    private func card(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    func testBrowseInstalledDownloadingSortFilterAndSearch() {
        runPasses { app, _ in
            XCTAssertTrue(app.buttons["Model"].waitForExistence(timeout: 15))
            openSettings(app)
            // The hub moved: Settings > Local Models > Browse all models.
            let local = button(app, containing: "Local Models")
            reveal(local, in: app)
            local.tap()
            let browse = button(app, containing: "Browse all models")
            reveal(browse, in: app)
            browse.tap()
            XCTAssertTrue(app.descendants(matching: .any)["hub.list"].waitForExistence(timeout: 10), "hub list")
            XCTAssertTrue(card(app, "Qwen3 0.6B").waitForExistence(timeout: 5), "installed model")
            step("hub-top")
            audit(app, "hub")

            let downloading = card(app, "Gemma 3 1B")
            var tries = 0
            while !downloading.isHittable && tries < 6 { app.swipeUp(); tries += 1 }
            XCTAssertTrue(downloading.isHittable, "the downloading model is listed")
            XCTAssertTrue(app.progressIndicators.firstMatch.exists || card(app, "42%").exists, "download progress is shown")
            step("hub-download-progress")
            app.swipeDown(); app.swipeDown(); app.swipeDown()

            app.buttons["hub.sort"].tap()
            let recommended = app.buttons["Recommended"]
            XCTAssertTrue(recommended.waitForExistence(timeout: 5), "sort menu opens")
            step("hub-sort-menu")
            recommended.tap()

            app.buttons["hub.filter"].tap()
            sleep(1)
            step("hub-filter-menu")
            // Tapping the menu button again closes the menu without touching a row.
            app.buttons["hub.filter"].tap()
            sleep(1)

            let search = app.searchFields["Search models"]
            search.tap()
            search.typeText("Llama")
            XCTAssertTrue(waitGone(card(app, "Qwen3 0.6B"), timeout: 5), "non-matching model leaves the list")
            XCTAssertTrue(card(app, "Llama 3.2 1B").waitForExistence(timeout: 5), "matching model stays")
            step("hub-search-llama")
        }
    }
}
