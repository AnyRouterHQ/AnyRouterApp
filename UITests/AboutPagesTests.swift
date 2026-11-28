import XCTest

/// Settings > About: the version row and the three pages under it (Diagnostics, Terms, Licenses), each opened and left again.
@MainActor
final class AboutPagesTests: XCTestCase {
    func testAboutShowsTheVersionAndItsThreePagesOpen() {
        let app = XCUIApplication.launchedOnDemoData()
        app.showSettingsPage("About")
        XCTAssertTrue(app.listRow("Version").waitForExistence(timeout: 5), "the version row is on the page")

        let content = ["Diagnostics": "Budget for a model", "Terms": "Apache License 2.0", "Licenses": "llama.cpp"]
        for page in ["Diagnostics", "Terms", "Licenses"] {
            let link = app.listRow(page)
            XCTAssertTrue(link.waitForExistence(timeout: 5), "\(page) is listed under the version")
            link.tap()
            XCTAssertTrue(app.navigationBars[page].waitForExistence(timeout: 10), "\(page) opened")
            XCTAssertTrue(app.labelled(containing: content[page] ?? "").waitForExistence(timeout: 10), "\(page) shows \(content[page] ?? "")")
            app.goBack(from: page, to: "About")
        }
    }
}
