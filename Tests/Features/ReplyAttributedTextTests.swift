import Testing
import UIKit
@testable import AnyRouter

/// A reply's text blocks are selectable in place: what is copied must be the words, not the markdown.
struct ReplyAttributedTextTests {
    private let reply = "# Title\n\nSome **bold** and `code` with a [link](https://example.com).\n\n- one\n- two\n\n1. first\n2. second\n\n```swift\nlet x = 1\n```"

    @Test func theTextIsTheReplyWithoutMarkdownSyntax() {
        let text = ReplyAttributedText.make(reply).string
        #expect(text == "Title\nSome bold and code with a link.\n•\tone\n•\ttwo\n1.\tfirst\n2.\tsecond\nlet x = 1")
    }

    private func attribute(_ key: NSAttributedString.Key, of word: String, in text: NSAttributedString) -> Any? {
        let range = (text.string as NSString).range(of: word)
        return range.location == NSNotFound ? nil : text.attribute(key, at: range.location, effectiveRange: nil)
    }

    @Test func codeIsMonospacedOnABackgroundAndProseIsNot() throws {
        let text = ReplyAttributedText.make(reply)
        let block = try #require(attribute(.font, of: "let x = 1", in: text) as? UIFont)
        let inline = try #require(attribute(.font, of: "code", in: text) as? UIFont)
        let prose = try #require(attribute(.font, of: "Some", in: text) as? UIFont)
        #expect(block.fontDescriptor.symbolicTraits.contains(.traitMonoSpace))
        #expect(inline.fontDescriptor.symbolicTraits.contains(.traitMonoSpace))
        #expect(!prose.fontDescriptor.symbolicTraits.contains(.traitMonoSpace))
        #expect(attribute(.backgroundColor, of: "let x = 1", in: text) as? UIColor == .secondarySystemFill)
        #expect(attribute(.backgroundColor, of: "code", in: text) as? UIColor == .secondarySystemFill, "the theme's inline code fill")
    }

    @Test func linksStayLinksAndHeadingsAndStrongAreBold() throws {
        let text = ReplyAttributedText.make(reply)
        #expect(attribute(.link, of: "link", in: text) as? URL == URL(string: "https://example.com"))
        let heading = try #require(attribute(.font, of: "Title", in: text) as? UIFont)
        let strong = try #require(attribute(.font, of: "bold", in: text) as? UIFont)
        #expect(heading.fontDescriptor.symbolicTraits.contains(.traitBold))
        #expect(strong.fontDescriptor.symbolicTraits.contains(.traitBold))
        #expect(heading.pointSize > strong.pointSize)
    }

    /// The size is the default-text-size body; the font scales from it like the rest of the app's text.
    @Test func theFontScalesFromTheGivenSizeWithDynamicType() throws {
        let text = ReplyAttributedText.make("plain words", size: 21)
        let font = try #require(text.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)
        #expect(font.pointSize == UIFontMetrics(forTextStyle: .body).scaledValue(for: 21))
    }

    /// A wrapped list line starts under the item's text, not under its bullet; a nested item is one indent further in.
    @Test func listItemsHangTheirWrappedLines() throws {
        let text = ReplyAttributedText.make("- one\n  - inner", size: 20)
        let outer = try #require(attribute(.paragraphStyle, of: "one", in: text) as? NSParagraphStyle)
        let inner = try #require(attribute(.paragraphStyle, of: "inner", in: text) as? NSParagraphStyle)
        #expect(outer.firstLineHeadIndent == 0 && outer.headIndent == 30)
        #expect(outer.tabStops.map(\.location) == [30])
        #expect(inner.firstLineHeadIndent == 30 && inner.headIndent == 60)
        let marker = try #require(text.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
        #expect(marker.headIndent == 30, "the bullet starts the paragraph, so it carries the item's style")
        let plain = try #require(ReplyAttributedText.make("words", size: 20).attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
        #expect(plain.headIndent == 0 && plain.lineSpacing == 5)
    }

    @Test func colorsAreSemanticSoDarkModeWorks() {
        let text = ReplyAttributedText.make("plain words")
        #expect(text.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor == .label)
    }
}
