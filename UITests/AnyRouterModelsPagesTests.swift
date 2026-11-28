import XCTest

/// Settings > AnyRouter Models, beyond star and hide (SettingsModelsTests): a hidden model shows on the Hidden page and
/// Show brings it back, and the Filter button opens the filters page.
@MainActor
final class AnyRouterModelsPagesTests: XCTestCase {
    func testAHiddenModelIsOnTheHiddenPageAndShowBringsItBack() {
        let app = XCUIApplication.launchedOnDemoData()
        app.showSettingsPage("AnyRouter Models")
        let model = app.buttons["model-row.anyrouter/openai/gpt-5"]
        XCTAssertTrue(model.waitForExistence(timeout: 10), "the model is listed")
        model.swipeLeft()
        app.buttons["Hide"].firstMatch.tap()

        let hidden = app.buttons["anyrouter.hidden"]
        app.scrollPage(under: app.navigationBars["AnyRouter Models"], until: hidden)
        XCTAssertTrue(hidden.isHittable, "a hidden model leaves a way back at the end of the list")
        hidden.tap()
        XCTAssertTrue(app.navigationBars["Hidden"].waitForExistence(timeout: 10), "the Hidden page opened")
        let show = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Show ")).firstMatch
        XCTAssertTrue(show.waitForExistence(timeout: 5), "the page offers Show for the model")
        show.tap()
        XCTAssertTrue(app.labelled(containing: "Nothing hidden").waitForExistence(timeout: 5), "with nothing hidden the page says so")
    }

    func testTheFilterButtonOpensTheFiltersPage() {
        let app = XCUIApplication.launchedOnDemoData()
        app.showSettingsPage("AnyRouter Models")
        let filter = app.buttons["anyrouter.filter"]
        XCTAssertTrue(filter.waitForExistence(timeout: 10), "the Filter button is in the bar")
        filter.tap()
        XCTAssertTrue(app.navigationBars["Filters"].waitForExistence(timeout: 10), "the filters page opened")
        XCTAssertTrue(app.switches["filter-free-only"].waitForExistence(timeout: 5), "it has the Free only switch")
        app.goBack(from: "Filters", to: "AnyRouter Models")
    }
}
