import Testing
@testable import AnyRouter

struct MarkdownBlocksTests {
    @Test func blankLinesSeparateBlocks() {
        #expect(MarkdownBlocks.split("one\n\ntwo\n\n\nthree") == ["one", "two", "three"])
    }

    @Test func emptyAndBlankTextHaveNoBlocks() {
        #expect(MarkdownBlocks.split("").isEmpty)
        #expect(MarkdownBlocks.split("\n\n  \n").isEmpty)
    }

    @Test func trailingNewlinesAreNotPartOfTheBlock() {
        #expect(MarkdownBlocks.split("one\n\n") == ["one"])
    }

    @Test func aBlankLineInsideACodeFenceDoesNotSplit() {
        let text = "intro\n\n```swift\nlet a = 1\n\nlet b = 2\n```\n\nafter"
        #expect(MarkdownBlocks.split(text) == ["intro", "```swift\nlet a = 1\n\nlet b = 2\n```", "after"])
    }

    @Test func anUnclosedFenceKeepsTheRestInOneBlock() {
        let text = "intro\n\n~~~\nline\n\nmore"
        #expect(MarkdownBlocks.split(text) == ["intro", "~~~\nline\n\nmore"])
    }

    @Test func listItemsSeparatedByBlankLinesStayTogether() {
        #expect(MarkdownBlocks.split("- a\n\n- b\n\n- c") == ["- a\n\n- b\n\n- c"])
        #expect(MarkdownBlocks.split("1. a\n\n2. b") == ["1. a\n\n2. b"])
    }

    @Test func aMarkerWithoutItsTextYetStillJoinsTheList() {
        #expect(MarkdownBlocks.split("- a\n\n-") == ["- a\n\n-"])
        #expect(MarkdownBlocks.split("1. a\n\n2.") == ["1. a\n\n2."])
    }

    @Test func anIndentedLineAfterABlankLineContinuesTheItem() {
        #expect(MarkdownBlocks.split("1. a\n\n   more\n\nnext") == ["1. a\n\n   more", "next"])
    }

    @Test func aParagraphAfterAListIsANewBlock() {
        #expect(MarkdownBlocks.split("- a\n- b\n\nplain") == ["- a\n- b", "plain"])
    }

    /// The reason for blocks: while text grows, every block except the last stays exactly as it was.
    @Test func growingTextNeverChangesEarlierBlocks() {
        let full = "# Title\n\nFirst paragraph.\n\n- one\n\n- two\n\n```swift\nlet a = 1\n\nlet b = 2\n```\n\n1. step\n\n   detail\n\nDone."
        let final = MarkdownBlocks.split(full)
        for end in full.indices {
            let blocks = MarkdownBlocks.split(String(full[...end]))
            let settled = Array(blocks.dropLast())
            #expect(Array(final.prefix(settled.count)) == settled)
        }
    }
}
