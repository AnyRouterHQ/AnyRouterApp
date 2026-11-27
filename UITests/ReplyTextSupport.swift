import XCTest

extension XCUIApplication {
    /// A reply's text block. Headings, lists and paragraphs are selectable text views, so their words are the value.
    func replyText(_ text: String) -> XCUIElement { replyTexts(text).firstMatch }

    func replyTexts(_ text: String) -> XCUIElementQuery {
        textViews.matching(NSPredicate(format: "value == %@", text))
    }
}
