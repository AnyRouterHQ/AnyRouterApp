import Foundation

/// Turns a web page into the text a model can read. Not a browser: scripts, styles and markup are dropped.
enum HTMLText {
    static func title(in html: String) -> String? {
        guard let match = titlePattern.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
            let range = Range(match.range(at: 1), in: html)
        else { return nil }
        let text = collapse(decode(String(html[range])))
        return text.isEmpty ? nil : text
    }

    static func readable(_ html: String) -> String {
        var text = html
        for pattern in dropPatterns { text = replace(pattern, in: text, with: " ") }
        text = replace(blockPattern, in: text, with: "\n")
        text = replace(tagPattern, in: text, with: "")
        text = decode(text)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map { collapse(String($0)) }
        // Blank lines collapse to one, so paragraphs stay apart without long gaps.
        var out: [String] = []
        for line in lines where !(line.isEmpty && (out.last?.isEmpty ?? true)) { out.append(line) }
        return out.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Helpers

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // The patterns are literals in this file; a typo shows up in the first test run.
        try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
    }

    private static let titlePattern = regex("<title[^>]*>(.*?)</title>")
    private static let dropPatterns = [
        regex("<script\\b.*?</script>"), regex("<style\\b.*?</style>"),
        regex("<noscript\\b.*?</noscript>"), regex("<svg\\b.*?</svg>"), regex("<!--.*?-->"),
        regex("<head\\b.*?</head>"),
    ]
    private static let blockPattern = regex("</?(p|div|br|li|ul|ol|tr|table|h[1-6]|section|article|header|footer|blockquote|pre)\\b[^>]*>")
    private static let tagPattern = regex("<[^>]*>")
    private static let spaces = regex("[ \\t\\u00A0]+")

    private static func replace(_ pattern: NSRegularExpression, in text: String, with template: String) -> String {
        pattern.stringByReplacingMatches(
            in: text, range: NSRange(text.startIndex..., in: text),
            withTemplate: NSRegularExpression.escapedTemplate(for: template))
    }

    private static func collapse(_ line: String) -> String {
        replace(spaces, in: line, with: " ").trimmingCharacters(in: .whitespaces)
    }

    private static let named: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
        "ndash": "–", "mdash": "—", "hellip": "…", "copy": "©",
    ]

    /// Named and numeric character references. Unknown ones stay as written.
    static func decode(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var out = ""
        var index = text.startIndex
        while index < text.endIndex {
            guard text[index] == "&", let semicolon = text[index...].prefix(12).firstIndex(of: ";") else {
                out.append(text[index])
                index = text.index(after: index)
                continue
            }
            let body = String(text[text.index(after: index)..<semicolon])
            if let replacement = entity(body) {
                out += replacement
                index = text.index(after: semicolon)
            } else {
                out.append("&")
                index = text.index(after: index)
            }
        }
        return out
    }

    private static func entity(_ body: String) -> String? {
        if body.hasPrefix("#") {
            let digits = body.dropFirst()
            let value = digits.hasPrefix("x") || digits.hasPrefix("X")
                ? UInt32(digits.dropFirst(), radix: 16) : UInt32(digits)
            return value.flatMap { Unicode.Scalar($0) }.map { String(Character($0)) }
        }
        return named[body.lowercased()]
    }
}
