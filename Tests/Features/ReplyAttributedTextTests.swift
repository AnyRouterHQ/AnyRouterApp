import Testing
import UIKit
@testable import AnyRouter

/// The Select Text sheet shows the reply as plain selectable text: what is copied must be the words, not the markdown.
struct ReplyAttributedTextTests {
    private let reply = "# Title\n\nSome **bold** and `code` with a [link](https://example.com).\n\n- one\n- two\n\n1. first\n2. second\n\n```swift\nlet x = 1\n```"

    @Test func theTextIsTheReplyWithoutMarkdownSyntax() {
        let text = ReplyAttributedText.make(reply).string
        #expect(text == "Title\nSome bold and code with a link.\n• one\n• two\n1. first\n2. second\nlet x = 1")
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
        #expect(attribute(.backgroundColor, of: "let x = 1", in: text) as? UIColor == .secondarySystemBackground)
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

    @Test func colorsAreSemanticSoDarkModeWorks() {
        let text = ReplyAttributedText.make("plain words")
        #expect(text.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor == .label)
    }
}
