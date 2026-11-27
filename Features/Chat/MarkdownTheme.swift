import MarkdownUI
import SwiftUI
import UIKit

extension Theme {
    /// Markdown look in system colors. `size` is the body size at the current Dynamic Type setting and reply text size
    /// (MarkdownUI takes points, so the view passes a scaled value); themes are cached per size and typeface.
    @MainActor static func anyRouter(size: CGFloat, font: ReplyFont = .system) -> Theme {
        let key = ThemeKey(size: Int(size.rounded()), font: font)
        if let cached = themes[key] { return cached }
        let theme = make(size: CGFloat(key.size), font: font)
        themes[key] = theme
        return theme
    }

    private struct ThemeKey: Hashable {
        let size: Int
        let font: ReplyFont
    }

    @MainActor private static var themes: [ThemeKey: Theme] = [:]

    @MainActor private static func make(size: CGFloat, font: ReplyFont) -> Theme {
        Theme()
            .text {
                FontFamily(.system(font.design))
                ForegroundColor(.primary)
                FontSize(size)
            }
            .code {
                FontFamilyVariant(.monospaced)
                FontSize(.em(0.88))
                BackgroundColor(Color(.secondarySystemFill))
            }
            .strong { FontWeight(.semibold) }
            .link { ForegroundColor(ARPalette.tint) }
            .heading1 { configuration in
                configuration.label
                    .markdownMargin(top: 20, bottom: 12)
                    .markdownTextStyle { FontWeight(.semibold); FontSize(.em(1.5)) }
            }
            .heading2 { configuration in
                configuration.label
                    .markdownMargin(top: 18, bottom: 10)
                    .markdownTextStyle { FontWeight(.semibold); FontSize(.em(1.3)) }
            }
            .heading3 { configuration in
                configuration.label
                    .markdownMargin(top: 16, bottom: 8)
                    .markdownTextStyle { FontWeight(.semibold); FontSize(.em(1.15)) }
            }
            .paragraph { configuration in
                configuration.label
                    .fixedSize(horizontal: false, vertical: true)
                    .relativeLineSpacing(.em(0.25))
                    .markdownMargin(top: 0, bottom: 12)
            }
            .listItem { configuration in
                configuration.label.markdownMargin(top: .em(0.25))
            }
            .blockquote { configuration in
                configuration.label
                    .padding(.leading, 12)
                    .overlay(alignment: .leading) {
                        Color(.separator).frame(width: 3)
                    }
                    .markdownTextStyle { ForegroundColor(.secondary) }
                    .markdownMargin(top: 0, bottom: 12)
            }
            .codeBlock { configuration in
                CodeBlockView(language: configuration.language, content: configuration.content)
                    .markdownMargin(top: 4, bottom: 12)
            }
            .table { configuration in
                // A wide table scrolls sideways instead of squeezing its columns.
                ScrollView(.horizontal, showsIndicators: false) {
                    configuration.label
                        .fixedSize(horizontal: true, vertical: true)
                        .markdownTableBorderStyle(.init(color: Color(.separator)))
                }
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                .markdownMargin(top: 0, bottom: 12)
            }
    }
}

/// Fenced code block: a rounded container with the language on the left and Copy on the right. Long lines scroll
/// sideways, a block of six lines or more gets line numbers, and keywords, strings and comments are coloured.
struct CodeBlockView: View {
    let language: String?
    let content: String

    /// From this many lines on, a block shows line numbers.
    static let lineNumberThreshold = 6

    @State private var hasMore = false

    private var code: String { content.trimmingCharacters(in: .newlines) }

    var body: some View {
        let lineCount = CodeBlockView.lineCount(code)
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text((language?.isEmpty == false ? language : nil) ?? "code")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                CopyButton(text: code, showsLabel: true)
            }
            .padding(.horizontal, 12)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    if lineCount >= CodeBlockView.lineNumberThreshold {
                        Text((1...lineCount).map(String.init).joined(separator: "\n"))
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                    Text(highlighted)
                        .textSelection(.enabled)
                }
                .font(.system(.callout, design: .monospaced))
                // Ideal size: a run showed the gutter and code cut to 10 lines ("10…", "Counter()…") when the row was measured short.
                .fixedSize(horizontal: true, vertical: true)
                .padding(12)
            }
            // A line that runs on fades at the edge instead of being cut mid-word; the fade goes when the end is reached.
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentSize.width - geometry.contentOffset.x - geometry.containerSize.width > 1
            } action: { _, more in
                hasMore = more
            }
            .mask {
                HStack(spacing: 0) {
                    Color.black
                    LinearGradient(colors: [.black, hasMore ? .clear : .black], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 28)
                }
            }
        }
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: ARTheme.radius))
    }

    static func lineCount(_ code: String) -> Int {
        code.isEmpty ? 1 : code.split(separator: "\n", omittingEmptySubsequences: false).count
    }

    private var highlighted: AttributedString {
        var result = AttributedString()
        for token in SyntaxHighlighter.tokens(code, language: language) {
            var piece = AttributedString(token.text)
            switch token.kind {
            case .plain: break
            case .keyword: piece.foregroundColor = .pink
            case .string: piece.foregroundColor = .red
            case .comment: piece.foregroundColor = Color(.secondaryLabel)
            }
            result.append(piece)
        }
        return result
    }
}

/// Copies text to the pasteboard and flips to a check mark for a moment, with a light tap.
struct CopyButton: View {
    let text: String
    var showsLabel = false
    /// The symbol's size when there is no label.
    var iconFont: Font = .footnote

    @State private var copied = false

    var body: some View {
        Button {
            UIPasteboard.general.string = text
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                copied = false
            }
        } label: {
            Group {
                if showsLabel {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .labelStyle(.titleAndIcon)
                        .font(.footnote)
                } else {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .labelStyle(.iconOnly)
                        .font(iconFont)
                }
            }
            // The HIG minimum hit area, inside the label: a frame outside a borderless button grows the layout
            // but not the button, so the audit still found a symbol-sized hit area.
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .sensoryFeedback(.impact(weight: .light), trigger: copied) { _, now in now }
        .accessibilityLabel("Copy")
    }
}
