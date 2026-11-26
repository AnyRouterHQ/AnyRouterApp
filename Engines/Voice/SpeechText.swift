import Foundation

/// Turns a markdown reply into the words worth reading aloud: no code blocks, links, URLs or markup.
/// It also works on a reply that is still streaming, so an open code block or link is dropped, not read.
enum SpeechText {
    private static let rules: [(pattern: String, template: String)] = [
        (#"(?s)```.*?```"#, " "),
        (#"(?s)```.*$"#, ""),
        (#"!\[[^\]]*\]\([^)]*\)"#, ""),
        (#"\[([^\]]*)\]\([^)]*\)"#, "$1"),
        (#"\]\([^)]*$"#, ""),
        (#"\[(?=[^\]]*$)"#, ""),
        (#"`([^`\n]*)`"#, "$1"),
        (#"`"#, ""),
        (#"https?://\S+"#, ""),
        (#"(?m)^ {0,3}#{1,6}[ \t]+"#, ""),
        (#"(?m)^[ \t]*>[ \t]?"#, ""),
        (#"(?m)^[ \t]*([-*_][ \t]*){3,}$"#, ""),
        (#"(?m)^[ \t]*[-*+\x{2022}][ \t]+"#, ""),
        (#"(?m)^[ \t]*\d{1,3}[.)][ \t]+"#, ""),
        (#"[*~]+|__"#, ""),
        (#"\|"#, ","),
        (#"[ \t]+"#, " "),
        (#"\n[ \t]*"#, "\n"),
        (#"\n{3,}"#, "\n\n"),
    ]

    static func clean(_ markdown: String) -> String {
        var text = markdown
        for rule in rules {
            text = text.replacingOccurrences(of: rule.pattern, with: rule.template, options: .regularExpression)
        }
        return text
    }
}
