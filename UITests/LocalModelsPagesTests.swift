import XCTest

/// Pages under Settings > Local Models that no other flow opens: the system model's page, and Advanced with the
/// catalog sources (the shared catalog's page, the repo field). Nothing is downloaded or added.
@MainActor
final class LocalModelsPagesTests: XCTestCase {
    func testTheSystemModelPageSetsTheDefaultAndLinksToSampling() {
        let app = XCUIApplication.launchedOnDemoData()
        app.showSettingsPage("Local Models")
        let apple = app.buttons["local.apple"]
        XCTAssertTrue(apple.waitForExistence(timeout: 10), "the system model is listed under System")
        apple.tap()

        let setDefault = app.buttons["Set as Default"]
        XCTAssertTrue(setDefault.waitForExistence(timeout: 10), "the demo default is a cloud model, so the system model can be made the default")
        setDefault.tap()
        XCTAssertTrue(app.labelled(containing: "Default model").waitForExistence(timeout: 5), "the page now says it is the default model")

        let sampling = app.buttons["Sampling and length"]
        XCTAssertTrue(sampling.exists, "the page links to sampling and length")
        sampling.tap()
        XCTAssertTrue(app.navigationBars["Response Customization"].waitForExistence(timeout: 10), "the generation settings opened")
        XCTAssertTrue(app.switches["settings-show-response-details"].waitForExistence(timeout: 5), "they are the Responses settings")
    }

    func testAdvancedListsTheCatalogSourceAndItsDevelopmentSwitchRenamesIt() {
        let app = XCUIApplication.launchedOnDemoData()
        app.showSettingsPage("Local Models")
        let advanced = app.buttons["local.advanced"]
        app.scrollPage(under: app.navigationBars["Local Models"], until: advanced)
        XCTAssertTrue(advanced.isHittable, "Advanced is reachable")
        advanced.tap()
        XCTAssertTrue(app.navigationBars["Advanced"].waitForExistence(timeout: 10), "the Advanced page opened")
        let sources = app.listRow("Catalog Sources")
        XCTAssertTrue(sources.waitForExistence(timeout: 5), "Advanced lists Catalog Sources")
        sources.tap()
        XCTAssertTrue(app.navigationBars["Catalog Sources"].waitForExistence(timeout: 10), "the sources page opened")

        let source = app.listRow("AnyRouter catalog")
        XCTAssertTrue(source.waitForExistence(timeout: 5), "the shared catalog is the first source")
        source.tap()
        XCTAssertTrue(app.navigationBars["AnyRouter catalog"].waitForExistence(timeout: 10), "the source's page opened")
        XCTAssertTrue(app.labelled(containing: "Address").waitForExistence(timeout: 5), "it shows where the list comes from")
        XCTAssertTrue(app.flipSwitch(app.switches["Use the development catalog"]), "the development catalog switch changed")
        XCTAssertTrue(app.navigationBars["AnyRouter catalog (development)"].waitForExistence(timeout: 5), "the source is named after the catalog it uses")
        app.goBack(from: "AnyRouter catalog (development)", to: "Catalog Sources")

        let add = app.buttons["Add repo"]
        XCTAssertTrue(add.waitForExistence(timeout: 5), "the page offers Add repo")
        XCTAssertFalse(add.isEnabled, "Add repo needs a repo")
        let field = app.element("catalog.repo.field")
        field.tap()
        field.typeText("acme/tiny-model")
        XCTAssertTrue(add.isEnabled, "a repo id enables Add repo")
    }
}
