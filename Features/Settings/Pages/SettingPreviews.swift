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
