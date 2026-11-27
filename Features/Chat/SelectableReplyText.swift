import SwiftUI
import UIKit

/// One text block of a reply (a heading, a list, a paragraph) in a read-only UITextView, so a long press selects any range
/// in place with the system's handles and Copy, Look Up, Translate and Share. SwiftUI's `Text` on iOS copies a whole text
/// only, and a context menu preview cannot take a drag, so the reply's actions stay in its footer.
struct SelectableReplyBlock: View, Equatable {
    let text: String
    /// The body size at the default text size; the fonts scale from it with Dynamic Type.
    let size: CGFloat
    /// The size MarkdownReply lays the other blocks out at. Only compared, so a text size change redraws the block.
    let scaledSize: CGFloat
    let font: ReplyFont

    var body: some View {
        SelectableReplyText(text: ReplyAttributedText.make(text, size: size, font: font))
    }
}

private struct SelectableReplyText: UIViewRepresentable {
    let text: NSAttributedString

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView(usingTextLayoutManager: true)
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        // The window tint turns blue under a Quick Look preview; links and handles take the app's mono accent instead.
        let tint = UIColor(named: "AccentColor") ?? .label
        view.tintColor = tint
        view.linkTextAttributes = [.foregroundColor: tint]
        view.adjustsFontForContentSizeCategory = true
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.accessibilityIdentifier = "reply.text"
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        guard view.attributedText != text else { return }
        view.attributedText = text
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? 10_000
        let fit = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? fit.width, height: ceil(fit.height))
    }
}
