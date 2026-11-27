import Foundation

/// The pure part of Extract: presets, the prompt, reading the model's JSON, and finding each quote in the document text.
enum ExtractLogic {
    static let customID = "custom"
    static let notFoundNote = "Not found in the text"
    static let noValueNote = "No value in the text"

    static let presets: [ExtractPreset] = [
        ExtractPreset(id: "receipt", title: "Receipt", fields: [
            FieldSpec("Merchant"), FieldSpec("Date", .date), FieldSpec("Total", .money),
            FieldSpec("Tax", .money), FieldSpec("Payment method"),
        ]),
        ExtractPreset(id: "bill", title: "Bill", fields: [
            FieldSpec("Provider"), FieldSpec("Account number"), FieldSpec("Billing period"),
            FieldSpec("Due date", .date), FieldSpec("Amount due", .money),
        ]),
        ExtractPreset(id: "invoice", title: "Invoice", fields: [
            FieldSpec("Vendor"), FieldSpec("Invoice number"), FieldSpec("Invoice date", .date),
            FieldSpec("Due date", .date), FieldSpec("Subtotal", .money), FieldSpec("Tax", .money),
            FieldSpec("Total", .money),
        ]),
        ExtractPreset(id: "email", title: "Email", fields: [
            FieldSpec("Sender"), FieldSpec("Subject"), FieldSpec("Date", .date),
            FieldSpec("Action requested"), FieldSpec("Deadline", .date),
        ]),
        ExtractPreset(id: customID, title: "Custom", fields: []),
    ]

    static func preset(id: String) -> ExtractPreset? { presets.first { $0.id == id } }

    // MARK: Fields the user adds

    /// `fields` with `field` added, unless its name is blank or already there (names are compared without case).
    static func adding(_ field: FieldSpec, to fields: [FieldSpec]) -> [FieldSpec] {
        let name = field.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let taken = fields.contains { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        guard !name.isEmpty, !taken else { return fields }
        return fields + [FieldSpec(name, field.kind, hint: field.hint)]
    }

    static func canExtract(text: String, fields: [FieldSpec]) -> Bool {
        !fields.isEmpty && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: Document text sent to the model

    /// A phone model has a small context, so it gets less of the document than a cloud model.
    static func characterLimit(for source: ModelSource) -> Int {
        switch source {
        case .apple, .gguf, .mlx: 6_000
        case .anyrouter: 40_000
        }
    }

    /// The first `limit` characters, and whether anything was cut. Offsets in the cut text are offsets in the full text.
    static func clipped(_ text: String, limit: Int) -> (text: String, isCut: Bool) {
        guard text.count > limit else { return (text, false) }
        return (String(text.prefix(limit)), true)
    }

    static func cutNote(limit: Int, total: Int) -> String {
        "Only the first \(limit) of \(total) characters are sent to this model."
    }

    // MARK: Prompt

    static func prompt(fields: [FieldSpec], text: String) -> String {
        let list = fields.map(fieldLine).joined(separator: "\n")
        let lines = [
            "Read the document below and extract these fields:",
            list,
            "",
            "Reply with only a JSON array, one object per field, in this shape:",
            ##"[{"name": "<field name>", "value": "<the value>", "quote": "<the words in the document it came from>"}]"##,
            "Rules: copy each quote exactly from the document, character for character, and keep it short.",
            "If the document does not have a field, give an empty string for its value and its quote.",
            "Do not add other text.",
            "",
            "Document:",
            text,
        ]
        return lines.joined(separator: "\n")
    }

    private static func fieldLine(_ field: FieldSpec) -> String {
        var line = "- \(field.name) (\(field.kind.instruction))"
        if let hint = field.hint, !hint.isEmpty { line += ": \(hint)" }
        return line
    }

    // MARK: Reply

    private struct Entry: Decodable {
        let name: String
        let value: Loose?
        let quote: String?
    }

    /// A value the model wrote as a string, a number or null.
    private struct Loose: Decodable {
        let text: String

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let string = try? container.decode(String.self) {
                text = string
            } else if let whole = try? container.decode(Int.self) {
                text = String(whole)
            } else if let fraction = try? container.decode(Double.self) {
                text = String(fraction)
            } else {
                text = ""
            }
        }
    }

    /// One result per requested field, in the order asked. A field the reply leaves out has an empty value and quote.
    /// Fences and prose around the JSON array are ignored; a reply with no readable array throws.
    static func parse(_ reply: String, fields: [FieldSpec], in text: String) throws -> [ExtractedField] {
        let entries = try entries(in: reply)
        return fields.map { spec in
            let entry = entries.first { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(spec.name) == .orderedSame }
            let value = entry?.value?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let quote = entry?.quote?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return ExtractedField(name: spec.name, kind: spec.kind, value: value, quote: quote, source: locate(quote, in: text))
        }
    }

    /// The first `[...]` in the reply that reads as a list of fields. Prose such as "see [1]" before it is skipped.
    private static func entries(in reply: String) throws -> [Entry] {
        let bytes = Array(reply.utf8)
        var from = 0
        while let open = bytes[from...].firstIndex(of: UInt8(ascii: "[")) {
            if let close = closingBracket(in: bytes, from: open),
               let entries = try? JSONDecoder().decode([Entry].self, from: Data(bytes[open...close])) {
                return entries
            }
            from = open + 1
        }
        throw ExtractError.unreadable
    }

    /// The `]` that closes the `[` at `open`, skipping brackets inside JSON strings.
    private static func closingBracket(in bytes: [UInt8], from open: Int) -> Int? {
        var depth = 0
        var inString = false
        var escaped = false
        for index in open..<bytes.count {
            let byte = bytes[index]
            if inString {
                if escaped {
                    escaped = false
                } else if byte == UInt8(ascii: "\\") {
                    escaped = true
                } else if byte == UInt8(ascii: "\"") {
                    inString = false
                }
            } else if byte == UInt8(ascii: "\"") {
                inString = true
            } else if byte == UInt8(ascii: "[") {
                depth += 1
            } else if byte == UInt8(ascii: "]") {
                depth -= 1
                if depth == 0 { return index }
            }
        }
        return nil
    }

    // MARK: Finding the quote

    /// The quote's character offsets in `text`: an exact match first, then one that ignores case and treats any run of
    /// whitespace as one space. Nil for an empty quote or one that is not there.
    static func locate(_ quote: String, in text: String) -> Range<Int>? {
        let needle = Array(quote.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !needle.isEmpty else { return nil }
        let haystack = Array(text)
        if let start = find(needle, in: haystack) { return start..<start + needle.count }
        let folded = fold(haystack)
        let foldedNeedle = fold(needle).map(\.character)
        guard let start = find(foldedNeedle, in: folded.map(\.character)) else { return nil }
        let last = start + foldedNeedle.count - 1
        return folded[start].origin..<folded[last].origin + 1
    }

    private static func find(_ needle: [Character], in haystack: [Character]) -> Int? {
        guard !needle.isEmpty, needle.count <= haystack.count else { return nil }
        for start in 0...(haystack.count - needle.count)
        where haystack[start] == needle[0] && haystack[start..<start + needle.count].elementsEqual(needle) {
            return start
        }
        return nil
    }

    /// Lowercased characters with each whitespace run as one space and none at the start, each with the offset of the
    /// original character it came from.
    private static func fold(_ characters: [Character]) -> [(character: Character, origin: Int)] {
        var folded: [(character: Character, origin: Int)] = []
        for (offset, character) in characters.enumerated() {
            if character.isWhitespace {
                if let last = folded.last, last.character != " " { folded.append((" ", offset)) }
            } else {
                for lowered in character.lowercased() { folded.append((lowered, offset)) }
            }
        }
        return folded
    }

    // MARK: Showing the source

    static func lines(of text: String) -> [DocumentLine] {
        var start = 0
        return text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).enumerated().map { index, line in
            defer { start += line.count + 1 }
            return DocumentLine(id: index, start: start, text: String(line))
        }
    }

    /// The id of the line a character offset falls on.
    static func lineID(containing offset: Int, in lines: [DocumentLine]) -> Int? {
        lines.last { $0.start <= offset }?.id
    }

    /// The parts of `ranges` that fall on `line`, as offsets inside the line.
    static func localRanges(_ ranges: [Range<Int>], in line: DocumentLine) -> [Range<Int>] {
        ranges.compactMap { range in
            let lower = max(range.lowerBound, line.start)
            let upper = min(range.upperBound, line.end)
            return lower < upper ? (lower - line.start)..<(upper - line.start) : nil
        }
    }

    /// A character range as string indices, or nil when it does not fit the text.
    static func stringRange(_ range: Range<Int>, in text: String) -> Range<String.Index>? {
        guard range.lowerBound >= 0, range.upperBound <= text.count else { return nil }
        let lower = text.index(text.startIndex, offsetBy: range.lowerBound)
        return lower..<text.index(lower, offsetBy: range.count)
    }

    // MARK: Results

    /// What the row says under a value that cannot be tied to the document.
    static func note(for field: ExtractedField) -> String? {
        if field.value.isEmpty { return noValueNote }
        return field.source == nil ? notFoundNote : nil
    }

    /// The fields as "Name: value" lines, for Share.
    static func exported(_ fields: [ExtractedField]) -> String {
        fields.filter { !$0.value.isEmpty }.map { "\($0.name): \($0.value)" }.joined(separator: "\n")
    }
}
