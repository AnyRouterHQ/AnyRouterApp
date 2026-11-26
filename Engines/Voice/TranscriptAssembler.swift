import Foundation

/// Builds one transcript from a recognizer's results: confirmed phrases plus the phrase still being revised.
struct TranscriptAssembler: Equatable, Sendable {
    private(set) var confirmed = ""
    private var tentative = ""

    var text: String { Self.join(confirmed, tentative) }

    mutating func apply(_ phrase: String, isFinal: Bool) {
        if isFinal {
            confirmed = Self.join(confirmed, phrase)
            tentative = ""
        } else {
            tentative = phrase
        }
    }

    private static func join(_ head: String, _ tail: String) -> String {
        let tail = tail.trimmingCharacters(in: .whitespacesAndNewlines)
        let head = head.trimmingCharacters(in: .whitespacesAndNewlines)
        if head.isEmpty { return tail }
        return tail.isEmpty ? head : head + " " + tail
    }
}
