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

    @Test func aFenceWithOrWithoutALanguageStaysOneBlock() {
        let plain = "before\n\n```\na\n\nb\n```\n\nafter"
        #expect(MarkdownBlocks.split(plain) == ["before", "```\na\n\nb\n```", "after"])
        let tilde = "~~~python\nx = 1\n\ny = 2\n~~~"
        #expect(MarkdownBlocks.split(tilde) == [tilde])
    }

    @Test func aTableIsOneBlockAndAParagraphAfterItIsAnother() {
        let table = "| a | b |\n|---|---|\n| 1 | 2 |\n| 3 | 4 |"
        #expect(MarkdownBlocks.split(table + "\n\nafter") == [table, "after"])
    }

    @Test func inlineCodeNeverSplitsABlock() {
        #expect(MarkdownBlocks.split("use `let` and `var`\n\nthen `x`") == ["use `let` and `var`", "then `x`"])
    }

    @Test func aFenceStillOpenWhileStreamingKeepsAllTheCodeInTheLastBlock() {
        let streaming = "intro\n\n```swift\nlet a = 1\n\nlet b"
        #expect(MarkdownBlocks.split(streaming) == ["intro", "```swift\nlet a = 1\n\nlet b"])
    }

    @Test func eachBlockIsKnownByItsFirstLine() {
        #expect(MarkdownBlocks.kind(of: "## Title") == .heading)
        #expect(MarkdownBlocks.kind(of: "```swift\nlet a = 1\n```") == .code)
        #expect(MarkdownBlocks.kind(of: "~~~\nx\n~~~") == .code)
        #expect(MarkdownBlocks.kind(of: "- one\n- two") == .list)
        #expect(MarkdownBlocks.kind(of: "1. one") == .list)
        #expect(MarkdownBlocks.kind(of: "Plain words") == .other)
        #expect(MarkdownBlocks.kind(of: "> quoted\n> more") == .quote)
        #expect(MarkdownBlocks.kind(of: "| a | b |\n|---|---|") == .table)
    }

    /// Text a long press can select in place; code, quotes and tables keep MarkdownUI's views.
    @Test func headingsListsAndParagraphsAreSelectableTextAndTheRestIsNot() {
        #expect(["# Title", "- one", "Plain words"].allSatisfy(MarkdownBlocks.isSelectableText))
        #expect(!["```\ncode\n```", "> quote", "| a |"].contains(where: MarkdownBlocks.isSelectableText))
        #expect(MarkdownBlocks.gap(before: "> quote", after: "Intro") == 0.7, "a quote keeps the paragraph gap it had as other")
        #expect(MarkdownBlocks.gap(before: "Outro", after: "| a |") == 0.7)
    }

    @Test func blocksAreSpacedByWhatTheyAre() {
        #expect(MarkdownBlocks.gap(before: "Second paragraph", after: "First paragraph") == 0.7)
        #expect(MarkdownBlocks.gap(before: "- item", after: "Key points:") == 0.9)
        #expect(MarkdownBlocks.gap(before: "Closing sentence.", after: "```\ncode\n```") == 0.9)
        #expect(MarkdownBlocks.gap(before: "```\ncode\n```", after: "Intro") == 0.9)
        #expect(MarkdownBlocks.gap(before: "Paragraph", after: "- item") == 0.9)
        #expect(MarkdownBlocks.gap(before: "## Next", after: "Paragraph") == 1.1)
        #expect(MarkdownBlocks.gap(before: "Text under it", after: "## Heading") == 0.4)
    }
}
