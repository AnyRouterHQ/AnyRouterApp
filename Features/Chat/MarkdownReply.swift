import MarkdownUI
import SwiftUI

/// An assistant reply as markdown blocks. Each block is an equatable view, so while a reply streams only the
/// last block is parsed and laid out again; the blocks above it are skipped. Headings, lists and paragraphs are
/// selectable in place by range (`SelectableReplyBlock`); a selection stays inside one block. Code, quotes and tables
/// keep MarkdownUI's views. The footer's Copy and the selection menu's Copy Reply copy the whole reply.
struct MarkdownReply: View {
    let text: String
    /// Read Aloud and Copy Reply in the selection menu; nil where there is no reply to act on (a settings preview).
    var menu: ReplyMenuActions?
    /// Scales with Dynamic Type. Passed to the blocks as a value, so a size change redraws them.
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 17
    /// Settings, Response Customization: the reply text size and typeface.
    @Environment(AppSettings.self) private var settings

    var body: some View {
        let signpost = Perf.signposter.beginInterval("markdown.split")
        let blocks = MarkdownBlocks.split(text)
        Perf.signposter.endInterval("markdown.split", signpost)
        let points = ReplyText.points(size, step: settings.replyTextStep)
        let base = ReplyText.points(17, step: settings.replyTextStep)
        let font = settings.replyFont
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                Group {
                    if MarkdownBlocks.isSelectableText(block) {
                        SelectableReplyBlock(text: block, size: base, scaledSize: points, font: font, menu: menu).equatable()
                    } else {
                        MarkdownBlock(text: block, size: points, font: font).equatable()
                    }
                }
                .padding(.top, index == 0 ? 0 : points * MarkdownBlocks.gap(before: block, after: blocks[index - 1]))
            }
        }
    }
}

private struct MarkdownBlock: View, Equatable {
    let text: String
    let size: CGFloat
    let font: ReplyFont

    var body: some View {
        Markdown(text)
            .markdownTheme(.anyRouter(size: size, font: font))
            .markdownImageProvider(BlockedImageProvider())
            .markdownInlineImageProvider(BlockedInlineImageProvider())
            .textSelection(.enabled)
    }
}
