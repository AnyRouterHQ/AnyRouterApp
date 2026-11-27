import SwiftUI
import UIKit

/// One text block of a reply (a heading, a list, a paragraph) in a read-only UITextView, so a long press selects any range
/// in place with the system's handles and Copy, Look Up, Translate and Share. SwiftUI's `Text` on iOS copies a whole text
/// only, and a context menu preview cannot take a drag. The selection menu gets "Remember" (the selection), "Read Aloud"
/// and "Copy Reply" (the whole reply) after the system's own items.
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

extension EnvironmentValues {
    /// The reply-level items of the selection menu. An environment value, not a field of the block, so the block keeps a
    /// plain synthesized `==` (a closure field made its conformance cross into the main actor, CI 46057480053).
    @Entry var replyMenuActions: ReplyMenuActions? = nil
}

/// What the selection menu of a reply can do with the whole reply.
struct ReplyMenuActions: Sendable {
    var isReading: @MainActor @Sendable () -> Bool
    var readAloud: @MainActor @Sendable () -> Void
    var copyReply: @MainActor @Sendable () -> Void
    /// Saves the selected text to memory. Nil while memory is off.
    var remember: (@MainActor @Sendable (String) -> Void)?
}

private struct SelectableReplyText: UIViewRepresentable {
    let text: NSAttributedString

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        var menu: ReplyMenuActions?

        func textView(_ textView: UITextView, editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
            guard let menu else { return UIMenu(children: suggestedActions) }
            let reading = menu.isReading()
            let read = UIAction(
                title: reading ? "Stop Reading" : "Read Aloud", image: UIImage(systemName: reading ? "stop" : "speaker.wave.2")
            ) { _ in MainActor.assumeIsolated { menu.readAloud() } }
            let copy = UIAction(title: "Copy Reply", image: UIImage(systemName: "doc.on.doc")) { _ in
                MainActor.assumeIsolated { menu.copyReply() }
            }
            var items: [UIMenuElement] = [read, copy]
            if let remember = menu.remember, range.length > 0 {
                let selected = (textView.text as NSString).substring(with: range)
                items.insert(UIAction(title: "Remember", image: UIImage(systemName: "brain")) { _ in
                    MainActor.assumeIsolated { remember(selected) }
                }, at: 0)
            }
            return UIMenu(children: suggestedActions + [UIMenu(options: .displayInline, children: items)])
        }
    }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView(usingTextLayoutManager: true)
        view.delegate = context.coordinator
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
        context.coordinator.menu = context.environment.replyMenuActions
        guard view.attributedText != text else { return }
        view.attributedText = text
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? 10_000
        let fit = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? fit.width, height: ceil(fit.height))
    }
}
