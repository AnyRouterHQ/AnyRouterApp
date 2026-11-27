import SwiftUI
import UIKit

/// The whole reply as one selectable text, for copying any part of it: the system handles, Copy, Look Up, Translate
/// and Share work on any range. Opens with nothing selected.
struct SelectTextSheet: View {
    let markdown: String
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SelectableText(text: ReplyAttributedText.make(
                markdown, size: ReplyText.points(17, step: settings.replyTextStep), font: settings.replyFont))
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Select Text")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }.accessibilityIdentifier("select-text.done")
                    }
                }
        }
        .presentationDetents([.large])
    }
}

/// A read-only UITextView: selectable, links tappable, fonts that follow Dynamic Type.
private struct SelectableText: UIViewRepresentable {
    let text: NSAttributedString

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isSelectable = true
        view.dataDetectorTypes = .link
        view.adjustsFontForContentSizeCategory = true
        view.backgroundColor = .systemBackground
        view.textContainerInset = UIEdgeInsets(top: 16, left: 12, bottom: 32, right: 12)
        view.accessibilityIdentifier = "select-text.view"
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        guard view.attributedText != text else { return }
        view.attributedText = text
    }
}
