import Foundation

/// The facts about the pasteboard that can be read without the system's "Allow Paste" alert.
protocol PasteboardProbe: Sendable {
    /// Bumped by the system each time anything is copied.
    var changeCount: Int { get }
    /// Whether text is there. Does not read it.
    var hasStrings: Bool { get }
    /// Whether a link is there. Does not read it.
    var hasURLs: Bool { get }
    /// Whether an image is there. Does not read it.
    var hasImages: Bool { get }
    /// Whether the text is probably a web link. Does not read it.
    func hasProbableWebURL() async -> Bool
}

extension PasteboardProbe {
    var hasURLs: Bool { false }
    var hasImages: Bool { false }
    func hasProbableWebURL() async -> Bool { false }
}

/// What was copied, known without reading it: it picks the chip's symbol and the quick actions offered.
enum ClipboardKind: String, Equatable, Sendable {
    case text, link, image

    var title: String {
        switch self {
        case .text: "Copied text"
        case .link: "Copied link"
        case .image: "Copied image"
        }
    }

    var symbol: String {
        switch self {
        case .text: "doc.on.clipboard"
        case .link: "link"
        case .image: "photo"
        }
    }
}

enum ClipboardLaunchLogic {
    /// Offer the clipboard row when text was copied since the last time one was offered, and the message is empty.
    /// A first launch has no last count, so whatever text is there is offered once.
    static func shouldOffer(changeCount: Int, lastSeen: Int?, hasStrings: Bool, composerEmpty: Bool) -> Bool {
        hasStrings && composerEmpty && changeCount != lastSeen
    }

    /// An image wins over a link, and a link over plain text: a copied link is also text.
    static func kind(hasStrings: Bool, hasURLs: Bool, hasImages: Bool) -> ClipboardKind? {
        if hasImages { return .image }
        if hasURLs { return .link }
        return hasStrings ? .text : nil
    }
}
