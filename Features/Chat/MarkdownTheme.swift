import MarkdownUI
import SwiftUI
import UIKit

extension Theme {
    /// Markdown look in system colors. `size` is the body size at the current Dynamic Type setting
    /// (MarkdownUI takes points, so the view passes a scaled value); themes are cached per size.
    @MainActor static func anyRouter(size: CGFloat) -> Theme {
        let key = Int(size.rounded())
        if let cached = themes[key] { return cached }
        let theme = make(size: CGFloat(key))
        themes[key] = theme
        return theme
    }

    @MainActor private static var themes: [Int: Theme] = [:]

    @MainActor private static func make(size: CGFloat) -> Theme {
        Theme()
            .text {
                ForegroundColor(.primary)
                FontSize(size)
            }
            .code {
                FontFamilyVariant(.monospaced)
                FontSize(.em(0.88))
                BackgroundColor(Color(.secondarySystemFill))
            }
            .strong { FontWeight(.semibold) }
            .link { ForegroundColor(.accentColor) }
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
                configuration.label
                    .fixedSize(horizontal: false, vertical: true)
                    .markdownTableBorderStyle(.init(color: Color(.separator)))
                    .markdownMargin(top: 0, bottom: 12)
            }
    }
}

/// Fenced code block with a language label and a copy button.
struct CodeBlockView: View {
    let language: String?
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text((language?.isEmpty == false ? language : nil) ?? "code")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                CopyButton(text: content, showsLabel: true)
            }
            .padding(.leading, 12)
            ScrollView(.horizontal, showsIndicators: false) {
                Text(content.trimmingCharacters(in: .newlines))
                    .font(.system(.callout, design: .monospaced))
                    .padding(12)
                    .textSelection(.enabled)
            }
        }
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: ARTheme.radius))
    }
}

/// Copies text to the pasteboard and flips to a check mark for a moment.
struct CopyButton: View {
    let text: String
    var showsLabel = false

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
            if showsLabel {
                Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                    .labelStyle(.titleAndIcon)
                    .font(.footnote)
            } else {
                Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                    .labelStyle(.iconOnly)
                    .font(.footnote)
            }
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        // The HIG minimum hit area; a borderless button is only as big as its content.
        .frame(minWidth: 44, minHeight: 44)
        .sensoryFeedback(.success, trigger: copied) { _, now in now }
        .accessibilityLabel("Copy")
    }
}
