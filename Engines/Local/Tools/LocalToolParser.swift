import Foundation

/// A tool call read out of a model's text.
struct ParsedToolCall: Equatable, Sendable {
    var name: String
    /// The arguments object as JSON text.
    var argumentsJSON: String
}

/// Reads tool calls out of the text a local model streams. Text that is not a call is passed on as it arrives; a call is
/// held back until the reply ends, so the reader never sees half of it. Anything that looks like a call but cannot be
/// read is given back as text, so nothing the model said is lost.
struct LocalToolParser {
    struct Finished: Equatable {
        /// What is left to show: held-back text, text around the calls, or a call that could not be read.
        var text: String
        var calls: [ParsedToolCall]
    }

    private static let pythonTag = "<|python_tag|>"

    private let format: LocalToolFormat?
    /// Text not shown yet because it may be the start of a call marker.
    private var held = ""
    private var captured = ""
    private var capturing = false
    /// Llama only: whether the first characters showed a call or plain text.
    private var decided = false

    /// `nil` passes every chunk through, for a request that must be answered without tools.
    init(format: LocalToolFormat?) {
        self.format = format
    }

    /// The part of `chunk` that is safe to show now.
    mutating func feed(_ chunk: String) -> String {
        guard let format else { return chunk }
        if capturing {
            captured += chunk
            return ""
        }
        if format == .llama { return feedLlama(chunk) }
        held += chunk
        let marker = format == .qwen ? "<tool_call>" : "```tool_code"
        if let range = held.range(of: marker) {
            let shown = String(held[..<range.lowerBound])
            captured = String(held[range.lowerBound...])
            held = ""
            capturing = true
            return shown
        }
        // The end of the text may be the start of the marker: keep that much back.
        let keep = (1..<marker.count).reversed().first { held.hasSuffix(String(marker.prefix($0))) } ?? 0
        let shown = String(held.dropLast(keep))
        held = String(held.suffix(keep))
        return shown
    }

    private mutating func feedLlama(_ chunk: String) -> String {
        if decided { return chunk }
        held += chunk
        let start = held.drop(while: \.isWhitespace)
        if start.isEmpty { return "" }
        if start.hasPrefix("{") || start.hasPrefix(Self.pythonTag) {
            captured = held
            held = ""
            capturing = true
            decided = true
            return ""
        }
        if start.count < Self.pythonTag.count, Self.pythonTag.hasPrefix(start) { return "" }
        decided = true
        defer { held = "" }
        return held
    }

    /// Call at the end of the reply.
    mutating func finish() -> Finished {
        guard let format, capturing else {
            defer { held = "" }
            return Finished(text: held, calls: [])
        }
        let parsed = Self.parse(captured, format: format)
        if parsed.calls.isEmpty { return Finished(text: held + captured, calls: []) }
        return Finished(text: parsed.rest, calls: parsed.calls)
    }

    // MARK: Reading

    private static func parse(_ text: String, format: LocalToolFormat) -> (calls: [ParsedToolCall], rest: String) {
        switch format {
        case .qwen: return blocks(in: text, open: "<tool_call>", close: "</tool_call>", read: readQwen)
        case .gemma: return blocks(in: text, open: "```tool_code", close: "```", read: readGemma)
        case .llama:
            var body = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if body.hasPrefix(pythonTag) { body.removeFirst(pythonTag.count) }
            for end in ["<|eom_id|>", "<|eot_id|>"] where body.hasSuffix(end) { body.removeLast(end.count) }
            if let call = readJSONCall(body.trimmingCharacters(in: .whitespacesAndNewlines)) { return ([call], "") }
            return ([], text)
        }
    }

    /// Every `open ... close` block (the close may be missing at the end of the text), the calls in them, and the text between.
    private static func blocks(
        in text: String, open: String, close: String, read: (String) -> [ParsedToolCall]
    ) -> (calls: [ParsedToolCall], rest: String) {
        var calls: [ParsedToolCall] = []
        var rest = ""
        var cursor = text[...]
        while let start = cursor.range(of: open) {
            rest += cursor[..<start.lowerBound]
            let inner = cursor[start.upperBound...]
            let end = inner.range(of: close)
            let body = end.map { inner[..<$0.lowerBound] } ?? inner
            let found = read(String(body))
            if found.isEmpty { rest += cursor[start.lowerBound..<(end?.upperBound ?? cursor.endIndex)] }
            calls += found
            cursor = end.map { inner[$0.upperBound...] } ?? ""
        }
        rest += cursor
        return (calls, rest.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func readQwen(_ body: String) -> [ParsedToolCall] {
        let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("{") { return readJSONCall(text).map { [$0] } ?? [] }
        return readXMLCall(text).map { [$0] } ?? []
    }

    /// `{"name": "x", "arguments": {...}}`, with "parameters" accepted for "arguments" and the arguments allowed as a JSON string.
    private static func readJSONCall(_ text: String) -> ParsedToolCall? {
        guard text.hasPrefix("{"), let value = JSONValue.parse(text), let name = value["name"]?.string, !name.isEmpty else { return nil }
        var arguments = value["arguments"] ?? value["parameters"] ?? .object([:])
        if let encoded = arguments.string, let decoded = JSONValue.parse(encoded) { arguments = decoded }
        guard arguments.object != nil else { return nil }
        return ParsedToolCall(name: name, argumentsJSON: arguments.jsonString())
    }

    /// Qwen 3 coder style: `<function=name><parameter=key>value</parameter></function>`.
    private static func readXMLCall(_ text: String) -> ParsedToolCall? {
        guard let name = firstMatch(#"<function=([^>\s]+)>"#, in: text)?.first, !name.isEmpty else { return nil }
        var arguments: [String: JSONValue] = [:]
        for match in matches(#"<parameter=([^>\s]+)>\s*(.*?)\s*</parameter>"#, in: text) where match.count == 2 {
            arguments[match[0]] = JSONValue.parse(match[1]) ?? .string(match[1])
        }
        return ParsedToolCall(name: name, argumentsJSON: JSONValue.object(arguments).jsonString())
    }

    private static func readGemma(_ body: String) -> [ParsedToolCall] {
        body.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .compactMap { line in readJSONCall(line) ?? PythonCall.parse(line) }
    }

    private static func firstMatch(_ pattern: String, in text: String) -> [String]? { matches(pattern, in: text).first }

    private static func matches(_ pattern: String, in text: String) -> [[String]] {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return [] }
        let whole = NSRange(text.startIndex..., in: text)
        return expression.matches(in: text, range: whole).map { match in
            (1..<match.numberOfRanges).compactMap { Range(match.range(at: $0), in: text).map { String(text[$0]) } }
        }
    }
}

/// `name(key="value", count=3, flag=True, tags=["a", "b"])`, the call a Gemma model writes. Keyword arguments only: a call with
/// positional arguments, or a value this reader does not know, is not read.
enum PythonCall {
    static func parse(_ line: String) -> ParsedToolCall? {
        var reader = Reader(Array(line))
        guard let call = reader.call(), reader.atEnd else { return nil }
        // The model sometimes wraps the call in print(...): read what is inside.
        if call.name == "print" { return call.inner.flatMap(parse) }
        guard let arguments = call.arguments else { return nil }
        return ParsedToolCall(name: call.name, argumentsJSON: JSONValue.object(arguments).jsonString())
    }

    private struct Call {
        var name: String
        var arguments: [String: JSONValue]?
        /// For print(...): the text between the brackets.
        var inner: String?
    }

    private struct Reader {
        private let chars: [Character]
        private var index = 0

        init(_ chars: [Character]) { self.chars = chars }

        var atEnd: Bool {
            var probe = index
            while probe < chars.count, chars[probe].isWhitespace { probe += 1 }
            return probe >= chars.count
        }

        private var peek: Character? { index < chars.count ? chars[index] : nil }

        private mutating func skipSpaces() {
            while index < chars.count, chars[index].isWhitespace { index += 1 }
        }

        private mutating func word(_ allowed: (Character) -> Bool) -> String {
            let start = index
            while index < chars.count, allowed(chars[index]) { index += 1 }
            return String(chars[start..<index])
        }

        /// `name(...)`, where the name may carry a module prefix (default_api.tool).
        mutating func call() -> Call? {
            skipSpaces()
            let full = word { $0.isLetter || $0.isNumber || "_.-".contains($0) }
            guard !full.isEmpty, peek == "(" else { return nil }
            let name = full.split(separator: ".").last.map(String.init) ?? full
            index += 1
            if name == "print" { return wrapped() }
            var arguments: [String: JSONValue] = [:]
            skipSpaces()
            if peek == ")" {
                index += 1
                return Call(name: name, arguments: arguments)
            }
            while true {
                skipSpaces()
                let key = word { $0.isLetter || $0.isNumber || $0 == "_" }
                skipSpaces()
                guard !key.isEmpty, peek == "=" else { return nil }
                index += 1
                guard let value = value() else { return nil }
                arguments[key] = value
                skipSpaces()
                if peek == "," {
                    index += 1
                } else if peek == ")" {
                    index += 1
                    return Call(name: name, arguments: arguments)
                } else {
                    return nil
                }
            }
        }

        /// The text up to the bracket that closes `print(`.
        private mutating func wrapped() -> Call? {
            var depth = 1
            var probe = index
            var quote: Character?
            while probe < chars.count, depth > 0 {
                let char = chars[probe]
                if let open = quote {
                    if char == open { quote = nil }
                } else if char == "\"" || char == "'" {
                    quote = char
                } else if char == "(" {
                    depth += 1
                } else if char == ")" {
                    depth -= 1
                }
                probe += 1
            }
            guard depth == 0 else { return nil }
            let inner = String(chars[index..<(probe - 1)])
            index = probe
            return Call(name: "print", inner: inner)
        }

        private mutating func value() -> JSONValue? {
            skipSpaces()
            guard let first = peek else { return nil }
            if first == "\"" || first == "'" { return string(quote: first).map(JSONValue.string) }
            if first == "[" { return list() }
            let text = word { !",)] ".contains($0) }
            switch text {
            case "True", "true": return .bool(true)
            case "False", "false": return .bool(false)
            case "None", "null": return .null
            default: return Double(text).map(JSONValue.number)
            }
        }

        private mutating func list() -> JSONValue? {
            index += 1
            var items: [JSONValue] = []
            skipSpaces()
            if peek == "]" {
                index += 1
                return .array(items)
            }
            while true {
                guard let item = value() else { return nil }
                items.append(item)
                skipSpaces()
                if peek == "," {
                    index += 1
                } else if peek == "]" {
                    index += 1
                    return .array(items)
                } else {
                    return nil
                }
            }
        }

        private mutating func string(quote: Character) -> String? {
            index += 1
            var result = ""
            while index < chars.count {
                let char = chars[index]
                index += 1
                if char == quote { return result }
                if char == "\\", index < chars.count {
                    let next = chars[index]
                    index += 1
                    result.append(next == "n" ? "\n" : next == "t" ? "\t" : next)
                } else {
                    result.append(char)
                }
            }
            return nil
        }
    }
}
