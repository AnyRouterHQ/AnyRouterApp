import XCTest

/// Settings > Integrations: the tool sources, one source's page, a source's switch, and the Add MCP server sheet.
/// Nothing is sent: Add stays off the network because the sheet is cancelled, and the connection test is never tapped.
@MainActor
final class IntegrationsSettingsTests: XCTestCase {
    func testASourcePageOpensAndItsSwitchFlips() {
        let app = XCUIApplication.launchedOnDemoData()
        app.showSettingsPage("Integrations")
        let source = app.switches["tools.source.deepwiki"]
        XCTAssertTrue(source.waitForExistence(timeout: 10), "DeepWiki is listed as a web source")
        XCTAssertTrue(app.switches["tools.source.device"].exists, "the on-device source is listed")

        app.buttons["tools.detail.deepwiki"].tap()
        XCTAssertTrue(app.navigationBars["DeepWiki"].waitForExistence(timeout: 10), "the source's page opened")
        XCTAssertTrue(app.labelled(containing: "Ask about a repository").waitForExistence(timeout: 10), "the page lists the source's tools")
        app.goBack(from: "DeepWiki", to: "Integrations")

        XCTAssertTrue(app.flipSwitch(app.switches["tools.source.deepwiki"]), "the source's switch changed")
    }

    func testAddMCPServerNeedsAnAddressAndCancelClosesIt() {
        let app = XCUIApplication.launchedOnDemoData()
        app.showSettingsPage("Integrations")
        let add = app.buttons["Add MCP server"]
        app.scrollPage(under: app.navigationBars["Integrations"], until: add)
        XCTAssertTrue(add.isHittable, "Add MCP server is reachable")
        add.tap()

        let sheet = app.navigationBars["Add MCP server"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 10), "the sheet opened")
        XCTAssertFalse(sheet.buttons["Add"].isEnabled, "Add needs an address")
        let url = app.element("mcp.add.url")
        XCTAssertTrue(url.waitForExistence(timeout: 5), "the address field is there")
        url.tap()
        url.typeText("https://example.com/mcp")
        XCTAssertTrue(sheet.buttons["Add"].isEnabled, "an address enables Add")

        sheet.buttons["Cancel"].tap()
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 5), "Cancel closes the sheet")
        XCTAssertTrue(app.navigationBars["Integrations"].exists, "back on the Integrations page")
    }
}
