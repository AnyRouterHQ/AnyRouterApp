import Foundation

/// The two facts about the pasteboard that can be read without the system's "Allow Paste" alert.
protocol PasteboardProbe: Sendable {
    /// Bumped by the system each time anything is copied.
    var changeCount: Int { get }
    /// Whether text is there. Does not read it.
    var hasStrings: Bool { get }
}

enum ClipboardLaunchLogic {
    /// Offer the clipboard row when text was copied since the last time one was offered, and the message is empty.
    /// A first launch has no last count, so whatever text is there is offered once.
    static func shouldOffer(changeCount: Int, lastSeen: Int?, hasStrings: Bool, composerEmpty: Bool) -> Bool {
        hasStrings && composerEmpty && changeCount != lastSeen
    }
}
