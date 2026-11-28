import Foundation

/// One thing to pull out of a document: a name, what kind of value it is, and an optional hint for the model.
struct FieldSpec: Identifiable, Hashable, Codable, Sendable {
    enum Kind: String, CaseIterable, Codable, Sendable {
        case text, number, date, money

        var title: String {
            switch self {
            case .text: "Text"
            case .number: "Number"
            case .date: "Date"
            case .money: "Money"
            }
        }

        /// How the prompt describes the value to the model.
        var instruction: String {
            switch self {
            case .text: "text"
            case .number: "a number"
            case .date: "a date written as YYYY-MM-DD"
            case .money: "an amount with its currency"
            }
        }
    }

    var name: String
    var kind: Kind
    var hint: String?

    var id: String { name }

    init(_ name: String, _ kind: Kind = .text, hint: String? = nil) {
        self.name = name
        self.kind = kind
        self.hint = hint
    }
}

/// A named list of fields for one kind of document. "custom" starts empty and the user adds fields.
struct ExtractPreset: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let fields: [FieldSpec]
    /// Wire ids of the model to ask first and the one to fall back to (`MiniAppModelChoice`).
    var preferredModel = "anyrouter/auto"
    var fallbackModel = "apple/foundation"

    var isCustom: Bool { id == ExtractLogic.customID }
}

/// One answer: the value the model read and the exact text it came from. `source` is the quote's character offsets in the
/// document text (Swift Characters, not UTF-16), or nil when the quote is not in the text.
struct ExtractedField: Identifiable, Hashable, Sendable {
    let name: String
    let kind: FieldSpec.Kind
    let value: String
    let quote: String
    let source: Range<Int>?

    var id: String { name }
}

enum ExtractError: Error, Equatable, LocalizedError {
    case unreadable
    case noText

    var errorDescription: String? {
        switch self {
        case .unreadable: "The model's answer could not be read. Try again or pick another model."
        case .noText: "There is no text to extract from."
        }
    }
}

/// One line of the document text with the character offset where it starts, so a field can scroll to and mark its source.
struct DocumentLine: Identifiable, Equatable, Sendable {
    let id: Int
    let start: Int
    let text: String

    var end: Int { start + text.count }
}
