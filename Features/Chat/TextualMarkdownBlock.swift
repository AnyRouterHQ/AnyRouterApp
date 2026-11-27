import SwiftUI
import Textual

/// Bakeoff (D26): one markdown block drawn by Textual, in the reply's typeface and size, with semantic colors only.
struct TextualMarkdownBlock: View {
    let text: String
    let size: CGFloat
    let font: ReplyFont

    var body: some View {
        StructuredText(markdown: text, syntaxExtensions: [.math])
            .font(.system(size: size, design: font.design))
            .foregroundStyle(.primary)
            .textual.codeBlockStyle(ReplyCodeBlockStyle())
            .textual.tableStyle(.overflow)
            .textual.textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Our code block chrome (language, Copy, sideways scroll) around Textual's highlighted text.
private struct ReplyCodeBlockStyle: StructuredText.CodeBlockStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(configuration.languageHint ?? "code")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Copy", systemImage: "doc.on.doc") { configuration.codeBlock.copyToPasteboard() }
                    .font(.footnote)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .padding(.horizontal, 12)
            ScrollView(.horizontal, showsIndicators: false) {
                configuration.label
                    .textual.fontScale(0.88)
                    .monospaced()
                    .fixedSize(horizontal: true, vertical: true)
                    .padding(12)
            }
        }
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: ARTheme.radius))
        .textual.blockSpacing(.fontScaled(top: 0.88, bottom: 0))
    }
}
