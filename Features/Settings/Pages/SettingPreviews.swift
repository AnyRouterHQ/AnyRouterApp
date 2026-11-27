import SwiftUI

/// A live, scaled-down reply under "Show response details": the real reply row fed with a fixed sample, so it follows
/// the app's own look. It cannot be tapped and reads as one line to VoiceOver.
struct ResponseDetailsPreview: View {
    let showsDetails: Bool
    @State private var sample = DemoData.sampleReply()

    var body: some View {
        MessageRow(message: sample, isStreamingThis: false, showsRegenerate: false, onRegenerate: {}, showsDetails: showsDetails)
            .frame(maxHeight: 120)
            .padding(.vertical, 4)
            .allowsHitTesting(false)
            .animation(.snappy, value: showsDetails)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(SettingsLogic.responseDetailsPreviewLabel(showsDetails))
            .accessibilityIdentifier("preview.response-details")
    }
}

/// A live reply in the chosen size and typeface, drawn by the real reply view so it can never drift from the chat.
/// It cannot be tapped and reads as one line to VoiceOver.
struct ReplyTextPreview: View {
    @Environment(AppSettings.self) private var settings

    static let sample = """
    A router sends each message to the model that suits it best.

    - Quick questions go to a fast model
    - Long ones go to a careful one

    Read **how it chose** in the details.
    """

    var body: some View {
        MarkdownReply(text: Self.sample)
            .padding(.vertical, 4)
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(ReplyText.previewLabel(step: settings.replyTextStep, font: settings.replyFont))
            .accessibilityIdentifier("preview.reply-text")
    }
}
