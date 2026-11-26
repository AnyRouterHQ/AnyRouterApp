import XCTest

/// A demo thread (launch argument `-ARDemoTools YES`) has a reply that searched the web.
/// The tool row is collapsed, says what was searched, and shows the result once expanded.
@MainActor
final class ToolRowTests: XCTestCase {
    func testToolRowIsCollapsedAndExpandsToTheResult() {
        let app = XCUIApplication()
        app.launchArguments = ["-ARDemoData", "YES", "-ARDemoTools", "YES"]
        app.launch()

        // iPhone: the thread list is a drawer behind the menu button. iPad: a column, open in landscape only.
        let thread = app.staticTexts["Latest Swift news"]
        app.revealSidebar(whenVisible: thread)
        // The drawer and the iPad column animate in; tap only once the row can take the tap.
        let tappable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: thread)
        XCTAssertEqual(XCTWaiter().wait(for: [tappable], timeout: 10), .completed, "the thread row never became tappable")
        thread.tap()
        // The drawer closes on iPhone but the iPad column stays, so the open chat is what proves the tap worked.

        let rows = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier == %@ AND label BEGINSWITH %@", "tool.row", "Searched the web for"))
        let row = rows.firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "tool row with a search title")

        let result = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "typed throws everywhere"))
        XCTAssertFalse(result.firstMatch.exists, "the result is hidden until the row is expanded")

        row.tap()
        XCTAssertTrue(result.firstMatch.waitForExistence(timeout: 5), "the result shows after expanding")
    }
}
