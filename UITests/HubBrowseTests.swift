import XCTest

/// Settings > Local Models > Browse all models, on the demo catalog: an installed model's page asks before it deletes,
/// search narrows the list, a family opens its sizes, and Add by link needs a repo. Nothing is downloaded or added.
@MainActor
final class HubBrowseTests: XCTestCase {
    private func openBrowse() -> XCUIApplication {
        let app = XCUIApplication.launchedOnDemoData()
        app.showSettingsPage("Local Models")
        let browse = app.listRow("Browse all models")
        app.scrollPage(under: app.navigationBars["Local Models"], until: browse)
        XCTAssertTrue(browse.isHittable, "Browse all models is reachable")
        browse.tap()
        XCTAssertTrue(app.navigationBars["Browse models"].waitForExistence(timeout: 10), "Browse models opened")
        return app
    }

    private func modelRow(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch
    }

    func testAnInstalledModelOpensItsPageAndDeleteAsksFirst() {
        let app = openBrowse()
        XCTAssertTrue(app.element("hub.storage").waitForExistence(timeout: 5), "the storage line is on top")
        let qwen = modelRow(app, "Qwen 3.5 0.8B")
        XCTAssertTrue(qwen.waitForExistence(timeout: 10), "an installed model is listed")
        qwen.tap()
        XCTAssertTrue(app.buttons["Set as Default"].waitForExistence(timeout: 10), "an installed model's page offers Set as Default")
        let delete = app.buttons["Delete"]
        app.scrollPage(under: app.navigationBars.firstMatch, until: delete)
        XCTAssertTrue(delete.isHittable, "Delete is reachable")
        delete.tap()
        let title = app.labelled(containing: "Delete Qwen 3.5 0.8B?")
        XCTAssertTrue(title.waitForExistence(timeout: 5), "Delete asks first")
        app.buttons["Cancel"].firstMatch.tap()
        XCTAssertTrue(title.waitForNonExistence(timeout: 5), "Cancel closes the question")
        XCTAssertTrue(app.buttons["Set as Default"].exists, "and stays on the model's page")
    }

    func testSearchNarrowsTheListAndAFamilyOpensItsSizes() {
        let app = openBrowse()
        let search = app.searchFields["Search models"]
        XCTAssertTrue(search.waitForExistence(timeout: 5), "the list is searchable")
        search.tap()
        search.typeText("Llama")
        XCTAssertTrue(modelRow(app, "Qwen 3.5 0.8B").waitForNonExistence(timeout: 5), "a model that does not match leaves the list")
        XCTAssertTrue(modelRow(app, "Llama 3.2 1B").waitForExistence(timeout: 5), "a matching model stays")
        search.buttons["Clear text"].tap()

        let inkling = app.listRow("Inkling 2 Mini")
        app.scrollPage(under: app.navigationBars["Browse models"], until: inkling)
        XCTAssertTrue(inkling.isHittable, "a family is listed under Available")
        inkling.tap()
        XCTAssertTrue(app.navigationBars["Inkling 2 Mini"].waitForExistence(timeout: 10), "the family page opened")
        XCTAssertTrue(app.labelled(containing: "Sizes").waitForExistence(timeout: 5), "it lists the family's sizes")
    }

    func testAddByLinkNeedsARepoAndCloseDismissesIt() {
        let app = openBrowse()
        app.buttons["hub.add"].tap()
        let sheet = app.navigationBars["Add by link"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 10), "the sheet opened")
        XCTAssertFalse(sheet.buttons["Add"].isEnabled, "Add needs a repo")
        let field = app.element("hub.add.field")
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("acme/tiny-model")
        XCTAssertTrue(sheet.buttons["Add"].isEnabled, "a repo id enables Add")
        sheet.buttons["Close"].tap()
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 5), "Close dismisses the sheet")
    }
}
