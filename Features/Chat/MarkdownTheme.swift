import MarkdownUI
import SwiftUI
import UIKit

extension Theme {
    /// Markdown look in AnyRouter colors.
    @MainActor static var anyRouter: Theme {
        Theme()
            .text {
                ForegroundColor(ARColor.foreground)
                FontSize(16)
            }
            .code {
                FontFamilyVariant(.monospaced)
                FontSize(.em(0.88))
                BackgroundColor(ARColor.muted)
            }
            .strong { FontWeight(.semibold) }
            .link { ForegroundColor(ARColor.accent) }
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
                        Rectangle().fill(ARColor.border).frame(width: 3)
                    }
                    .markdownTextStyle { ForegroundColor(ARColor.mutedForeground) }
                    .markdownMargin(top: 0, bottom: 12)
            }
            .codeBlock { configuration in
                CodeBlockView(language: configuration.language, content: configuration.content)
                    .markdownMargin(top: 4, bottom: 12)
            }
            .table { configuration in
                configuration.label
                    .fixedSize(horizontal: false, vertical: true)
                    .markdownTableBorderStyle(.init(color: ARColor.border))
                    .markdownMargin(top: 0, bottom: 12)
            }
    }
}

/// Fenced code block with a language label and a copy button.
struct CodeBlockView: View {
    let language: String?
    let content: String

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text((language?.isEmpty == false ? language : nil) ?? "code")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ARColor.mutedForeground)
                Spacer()
                CopyButton(text: content, showsLabel: true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(ARColor.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                Text(content.trimmingCharacters(in: .newlines))
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(ARColor.foreground)
                    .padding(12)
                    .textSelection(.enabled)
            }
        }
        .background(ARColor.muted.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: ARTheme.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: ARTheme.radius, style: .continuous).strokeBorder(ARColor.border, lineWidth: 1))
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
            HStack(spacing: 4) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                if showsLabel { Text(copied ? "Copied" : "Copy") }
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(ARColor.mutedForeground)
            .frame(minWidth: 28, minHeight: 28)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Copy")
    }
}
