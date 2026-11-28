import XCTest

/// Settings > Responses > Custom Instructions: a template fills the editor, Clear empties it again.
@MainActor
final class CustomInstructionsSettingsTests: XCTestCase {
    func testATemplateFillsTheEditorAndClearEmptiesIt() {
        let app = XCUIApplication.launchedOnDemoData()
        app.showSettingsPage("Responses")
        let link = app.buttons["settings-custom-instructions"]
        app.scrollPage(under: app.navigationBars["Responses"], until: link)
        XCTAssertTrue(link.isHittable, "Custom instructions is reachable on the Responses page")
        link.tap()
        XCTAssertTrue(app.navigationBars["Custom Instructions"].waitForExistence(timeout: 10), "the page opened")

        let editor = app.textViews["instructions.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertFalse(app.words(of: editor).contains("Answer briefly"), "the editor starts empty")
        let template = app.buttons["instructions.template.concise"]
        app.scrollPage(under: app.navigationBars["Custom Instructions"], until: template)
        template.tap()
        XCTAssertTrue(FlowWait.until(5) { app.words(of: editor).contains("Answer briefly and directly") }, "the template is in the editor")

        let clear = app.buttons["Clear"]
        app.scrollPage(under: app.navigationBars["Custom Instructions"], until: clear)
        clear.tap()
        XCTAssertTrue(FlowWait.until(5) { !app.words(of: editor).contains("Answer briefly") }, "Clear empties the editor")
    }
}
