import SwiftStreamingMarkdown
import SwiftUI
import UIKit

/// Bakeoff (D26): one markdown block drawn by SwiftStreamingMarkdown (UIKit paragraphs under SwiftUI blocks), in the
/// reply's typeface and size, with semantic colors only. Its own code block chrome and highlighter are used.
struct StreamingMarkdownBlock: View {
    let text: String
    let size: CGFloat
    let font: ReplyFont

    var body: some View {
        MarkdownView(text: text, config: StreamingMarkdownTheme.config(size: size, font: font))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

@MainActor
enum StreamingMarkdownTheme {
    private struct Key: Hashable {
        let size: Int
        let font: ReplyFont
    }

    private static var cache: [Key: MarkdownRenderConfig] = [:]

    static func config(size: CGFloat, font: ReplyFont) -> MarkdownRenderConfig {
        let key = Key(size: Int(size.rounded()), font: font)
        if let cached = cache[key] { return cached }
        let config = make(size: CGFloat(key.size), design: design(font))
        cache[key] = config
        return config
    }

    private static func design(_ font: ReplyFont) -> UIFontDescriptor.SystemDesign {
        switch font {
        case .system: .default
        case .serif: .serif
        case .rounded: .rounded
        }
    }

    private static func face(_ size: CGFloat, _ design: UIFontDescriptor.SystemDesign, _ weight: UIFont.Weight, italic: Bool) -> UIFont {
        var descriptor = UIFont.systemFont(ofSize: size, weight: weight).fontDescriptor
        if let designed = descriptor.withDesign(design) { descriptor = designed }
        if italic, let slanted = descriptor.withSymbolicTraits(descriptor.symbolicTraits.union(.traitItalic)) { descriptor = slanted }
        return UIFont(descriptor: descriptor, size: size)
    }

    private static func fonts(_ size: CGFloat, _ design: UIFontDescriptor.SystemDesign, weight: UIFont.Weight = .regular) -> TextFonts {
        TextFonts(
            normal: face(size, design, weight, italic: false), italic: face(size, design, weight, italic: true),
            bold: face(size, design, .semibold, italic: false), boldItalic: face(size, design, .semibold, italic: true),
            preferredLetterSpacing: nil, preferredLineHeight: size * 1.3)
    }

    private static func make(size: CGFloat, design: UIFontDescriptor.SystemDesign) -> MarkdownRenderConfig {
        let body = fonts(size, design)
        let mono = UIFont.monospacedSystemFont(ofSize: size * 0.88, weight: .regular)
        let monoFonts = TextFonts(normal: mono, italic: nil, bold: nil, boldItalic: nil, preferredLetterSpacing: nil, preferredLineHeight: nil)
        return MarkdownRenderConfig(
            blockQuoteStyle: .init(textFonts: body, textColor: .secondary),
            headingStyle: .init(
                h1Font: fonts(size * 1.5, design, weight: .semibold), h2Font: fonts(size * 1.3, design, weight: .semibold),
                h3Font: fonts(size * 1.15, design, weight: .semibold), h4Font: fonts(size, design, weight: .semibold),
                h5Font: fonts(size, design, weight: .semibold), h6Font: fonts(size, design, weight: .semibold),
                textColor: .primary),
            orderedListStyle: .init(textFonts: body, textColor: .primary),
            paragraphStyle: .init(textFonts: body, textColor: .primary),
            tableStyle: .init(
                textFonts: fonts(size * 0.88, design), headerTextColor: .primary, regularTextColor: .primary,
                headerBackgroundColor: Color(.secondarySystemFill), borderColor: Color(.separator), actionButtonColor: .accentColor),
            inlineStyle: .init(
                boldTextColor: .primary, linkTextFont: body.normal, linkTextColor: .accentColor, codeTextFont: mono,
                codeTextColor: .primary, codeBackgroundColor: Color(.secondarySystemFill), codeUnderlineColor: .clear),
            codeBlockConfig: CodeBlockConfig(
                theme: .xcode, backgroundColor: Color(.secondarySystemBackground), foregroundColor: .secondary,
                codeTextFonts: monoFonts, chromeTextFonts: fonts(13, .default)),
            blockSpacing: size * 0.7,
            textSelectionConfig: TextSelectionConfig(isEnabled: true, backgroundColor: Color(.systemBackground)))
    }
}
