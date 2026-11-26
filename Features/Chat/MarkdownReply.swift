import MarkdownUI
import SwiftUI

/// An assistant reply as markdown blocks. Each block is an equatable view, so while a reply streams only the
/// last block is parsed and laid out again; the blocks above it are skipped. (Selection works inside a block,
/// not across blocks; the Copy button copies the whole reply.)
struct MarkdownReply: View {
    let text: String

    var body: some View {
        let signpost = Perf.signposter.beginInterval("markdown.split")
        let blocks = MarkdownBlocks.split(text)
        Perf.signposter.endInterval("markdown.split", signpost)
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                MarkdownBlock(text: block).equatable()
            }
        }
    }
}

private struct MarkdownBlock: View, Equatable {
    let text: String

    var body: some View {
        Markdown(text)
            .markdownTheme(.anyRouter)
            .textSelection(.enabled)
    }
}
