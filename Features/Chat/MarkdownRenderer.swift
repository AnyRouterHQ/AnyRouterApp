import Foundation

/// Bakeoff (D26): which library draws a reply's markdown. MarkdownUI is the control. The default is set per commit on
/// exp/markdown-renderer so a perf or screenshots run measures one renderer; `-ARMarkdownRenderer textual` overrides it.
enum MarkdownRenderer: String {
    case markdownUI, textual, streaming

    static let defaultKind: MarkdownRenderer = .textual

    static let current: MarkdownRenderer =
        UserDefaults.standard.string(forKey: "ARMarkdownRenderer").flatMap(MarkdownRenderer.init(rawValue:)) ?? defaultKind
}
