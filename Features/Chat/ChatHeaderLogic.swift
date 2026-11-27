import Foundation

/// What the chat's top bar shows above the model name.
enum ChatHeaderLogic {
    /// The chat's title once it has a reply; before that the title is only the first message's words or "New chat".
    /// Nil leaves the model name alone in the bar.
    static func title(_ threadTitle: String?, hasReply: Bool) -> String? {
        guard hasReply, let title = threadTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { return nil }
        return title
    }
}
