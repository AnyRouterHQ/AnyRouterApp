import Foundation

/// The words VoiceOver gets that no view can show by itself.
enum AccessibilityLogic {
    /// Spoken once when a reply stops streaming with text. A failed or empty reply has its own message and says nothing here.
    static func replyFinishedAnnouncement(wasStreaming: Bool, isStreaming: Bool, hasContent: Bool, failed: Bool) -> String? {
        guard wasStreaming, !isStreaming, hasContent, !failed else { return nil }
        return "Reply finished"
    }

    /// The model pill reads "Model, <value>": the name, or why there is none yet.
    static func modelPillValue(name: String?, isLoading: Bool) -> String {
        name ?? (isLoading ? "Loading" : "None chosen")
    }
}
