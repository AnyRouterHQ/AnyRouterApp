import Foundation
import UIKit

/// A reply's markdown as rendered text for the Select Text sheet: no markdown syntax left, headings bold, list items
/// with a bullet or number, code in monospace on a secondary background, links as links. Fonts scale with Dynamic Type
/// and colors are semantic, so it is right in dark mode.
enum ReplyAttributedText {
    static func make(_ markdown: String, size: CGFloat = 17, font: ReplyFont = .system) -> NSAttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .full, failurePolicy: .returnPartiallyParsedIfPossible)
        guard let parsed = try? AttributedString(markdown: markdown, options: options) else {
            return NSAttributedString(string: markdown, attributes: [.font: face(size, font), .foregroundColor: UIColor.label])
        }
        let out = NSMutableAttributedString()
        var block: PresentationIntent?
        for run in parsed.runs {
            var text = String(parsed[run.range].characters)
            let intent = run.presentationIntent
            let kinds = intent?.components.map(\.kind) ?? []
            let isCode = kinds.contains { if case .codeBlock = $0 { true } else { false } }
            if isCode { text = text.trimmingCharacters(in: .newlines) }
            if intent != block {
                if out.length > 0 { out.append(NSAttributedString(string: "\n")) }
                out.append(NSAttributedString(string: listMarker(kinds), attributes: [.font: face(size, font), .foregroundColor: UIColor.secondaryLabel]))
                block = intent
            }
            out.append(NSAttributedString(string: text, attributes: attributes(run, kinds: kinds, isCode: isCode, size: size, font: font)))
        }
        return out
    }

    /// "• " or "2. " for the first run of a list item, indented one tab per level of nesting.
    private static func listMarker(_ kinds: [PresentationIntent.Kind]) -> String {
        var depth = 0
        var ordinal: Int?
        var ordered = false
        for (index, kind) in kinds.enumerated() {
            switch kind {
            case .listItem(let number):
                depth += 1
                if ordinal == nil {
                    ordinal = number
                    if index + 1 < kinds.count, case .orderedList = kinds[index + 1] { ordered = true }
                }
            default: break
            }
        }
        guard let ordinal else { return "" }
        return String(repeating: "\t", count: depth - 1) + (ordered ? "\(ordinal). " : "• ")
    }

    private static func attributes(
        _ run: AttributedString.Runs.Run, kinds: [PresentationIntent.Kind], isCode: Bool, size: CGFloat, font: ReplyFont
    ) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [.foregroundColor: UIColor.label]
        let inline = run.inlinePresentationIntent ?? []
        var level: Int?
        for kind in kinds { if case .header(let value) = kind { level = value } }
        if isCode || inline.contains(.code) {
            attributes[.font] = UIFontMetrics(forTextStyle: .body).scaledFont(for: .monospacedSystemFont(ofSize: size * 0.88, weight: .regular))
            attributes[.backgroundColor] = UIColor.secondarySystemBackground
        } else {
            let scale: CGFloat
            switch level ?? 0 {
            case 1: scale = 1.5
            case 2: scale = 1.3
            case 3: scale = 1.15
            default: scale = 1
            }
            let bold = level != nil || inline.contains(.stronglyEmphasized)
            attributes[.font] = face(size * scale, font, bold: bold, italic: inline.contains(.emphasized))
        }
        if let link = run.link { attributes[.link] = link }
        if inline.contains(.strikethrough) { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacing = size * 0.6
        paragraph.lineSpacing = size * 0.2
        attributes[.paragraphStyle] = paragraph
        return attributes
    }

    static func face(_ size: CGFloat, _ font: ReplyFont, bold: Bool = false, italic: Bool = false) -> UIFont {
        var descriptor = UIFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular).fontDescriptor
        let design: UIFontDescriptor.SystemDesign
        switch font {
        case .system: design = .default
        case .serif: design = .serif
        case .rounded: design = .rounded
        }
        if let designed = descriptor.withDesign(design) { descriptor = designed }
        if italic, let slanted = descriptor.withSymbolicTraits(descriptor.symbolicTraits.union(.traitItalic)) { descriptor = slanted }
        return UIFontMetrics(forTextStyle: .body).scaledFont(for: UIFont(descriptor: descriptor, size: size))
    }
}
