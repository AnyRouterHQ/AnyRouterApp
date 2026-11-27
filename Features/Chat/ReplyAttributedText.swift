import Foundation
import UIKit

/// A text block of a reply as the attributed text its selectable view shows: no markdown syntax left, headings bold,
/// list items with a hanging bullet or number, code in monospace on a fill, links as links. `size` is the body size at the
/// default text size (with the reply text size step); fonts scale from it with Dynamic Type, so the text view can follow
/// the setting itself. Colors are semantic, so dark mode works.
enum ReplyAttributedText {
    static func make(_ markdown: String, size: CGFloat = 17, font: ReplyFont = .system) -> NSAttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .full, failurePolicy: .returnPartiallyParsedIfPossible)
        guard let parsed = try? AttributedString(markdown: markdown, options: options) else {
            return NSAttributedString(string: markdown, attributes: [.font: face(size, font), .foregroundColor: UIColor.label])
        }
        let out = NSMutableAttributedString()
        var block: PresentationIntent?
        var last: [NSAttributedString.Key: Any] = [:]
        for run in parsed.runs {
            var text = String(parsed[run.range].characters)
            let intent = run.presentationIntent
            let kinds = intent?.components.map(\.kind) ?? []
            let isCode = kinds.contains { if case .codeBlock = $0 { true } else { false } }
            if isCode { text = text.trimmingCharacters(in: .newlines) }
            let paragraph = paragraphStyle(kinds, size: size)
            if intent != block {
                if out.length > 0 { out.append(NSAttributedString(string: "\n", attributes: last)) }
                out.append(NSAttributedString(string: listMarker(kinds), attributes: [
                    .font: face(size, font), .foregroundColor: UIColor.secondaryLabel, .paragraphStyle: paragraph,
                ]))
                block = intent
            }
            var attributes = attributes(run, kinds: kinds, isCode: isCode, size: size, font: font)
            attributes[.paragraphStyle] = paragraph
            out.append(NSAttributedString(string: text, attributes: attributes))
            last = attributes
        }
        return out
    }

    private static func listDepth(_ kinds: [PresentationIntent.Kind]) -> Int {
        kinds.filter { if case .listItem = $0 { true } else { false } }.count
    }

    /// "•" or "2." and a tab for the first run of a list item. The tab stop sits where wrapped lines start.
    private static func listMarker(_ kinds: [PresentationIntent.Kind]) -> String {
        for (index, kind) in kinds.enumerated() {
            guard case .listItem(let number) = kind else { continue }
            let ordered: Bool
            if index + 1 < kinds.count, case .orderedList = kinds[index + 1] { ordered = true } else { ordered = false }
            return (ordered ? "\(number)." : "•") + "\t"
        }
        return ""
    }

    /// The line spacing of the markdown theme; a list item hangs its wrapped lines under its text, one indent per level.
    private static func paragraphStyle(_ kinds: [PresentationIntent.Kind], size base: CGFloat) -> NSParagraphStyle {
        let size = UIFontMetrics(forTextStyle: .body).scaledValue(for: base)
        let depth = listDepth(kinds)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = size * 0.25
        paragraph.paragraphSpacing = size * (depth > 0 ? 0.25 : 0.6)
        if depth > 0 {
            let indent = size * 1.5
            paragraph.headIndent = indent * CGFloat(depth)
            paragraph.firstLineHeadIndent = indent * CGFloat(depth - 1)
            paragraph.tabStops = [NSTextTab(textAlignment: .natural, location: paragraph.headIndent, options: [:])]
            paragraph.defaultTabInterval = indent
        }
        return paragraph
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
            attributes[.backgroundColor] = UIColor.secondarySystemFill
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
