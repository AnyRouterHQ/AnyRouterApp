import Foundation

/// The composer text the clipboard use cases start from. No UI, so it is tested directly.
enum UseCaseLogic {
    /// "Ask about the clipboard": the copied text under a short lead-in, and the cursor on the question. Nil when nothing
    /// useful was copied.
    static func clipboardQuestion(_ clipboard: String) -> String? {
        let body = clipboard.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return nil }
        return "About this text:\n\(body)\n\nMy question: "
    }

    /// The first web address in the copied text.
    static func firstLink(in text: String) -> URL? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..., in: text)
        return detector?.matches(in: text, range: range)
            .compactMap(\.url)
            .first { ["http", "https"].contains($0.scheme?.lowercased()) }
    }

    /// "Summarize a link": with a link copied the request is ready to send; without one the composer gets the lead-in and
    /// the person pastes the link.
    static func linkRequest(_ clipboard: String) -> (text: String, isReady: Bool) {
        guard let url = firstLink(in: clipboard) else { return ("Summarize this page:\n", false) }
        return ("Summarize this page in a few short points:\n\(url.absoluteString)", true)
    }

    /// Said under the composer when a link was copied but the model cannot open pages.
    static func cannotOpenLinks(_ modelName: String) -> String {
        "\(modelName) cannot open links. Choose a model with tools to summarize a page."
    }
}
