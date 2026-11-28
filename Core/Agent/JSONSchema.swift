import Foundation

/// A tool's arguments schema (agent v2 K1a, docs/research/agent-v2.md). It keeps the whole JSON Schema the tool gives:
/// MCP servers send anything (anyOf, minimum, formats), and cloud models get it unchanged. Typed readers cover the
/// subset the app's own code reads: Apple's generation schema and the local tool text. Its text form always has sorted
/// keys, so a request's bytes are the same from run to run.
struct JSONSchema: Hashable, Sendable, ExpressibleByStringLiteral {
    var value: JSONValue

    init(_ value: JSONValue) {
        self.value = value
    }

    /// JSON text. Text that is not JSON reads as an object with no properties.
    init(parsing text: String) {
        value = JSONValue.parse(text) ?? Self.noArguments
    }

    init(stringLiteral text: String) {
        self.init(parsing: text)
    }

    /// An arguments object with no properties.
    static let noArguments: JSONValue = .object(["type": .string("object"), "properties": .object([:])])

    /// Nesting deeper than this reads as a string in `shape`: the on-device model's context is small.
    static let maxDepth = 5

    /// The schema as JSON text with sorted keys.
    var json: String { value.jsonString() }

    /// What a request sends as a tool's parameters: the schema when it is an object, else no arguments.
    var wireObject: JSONValue { value.object == nil ? Self.noArguments : value }

    var description: String? {
        guard let text = value["description"]?.string, !text.isEmpty else { return nil }
        return text
    }

    /// `type`; for a list such as `["string", "null"]`, its first entry that is not null; else "object" when the schema
    /// has properties.
    var typeName: String? {
        if let name = value["type"]?.string { return name }
        if let first = value["type"]?.array?.compactMap(\.string).first(where: { $0 != "null" }) { return first }
        return value["properties"]?.object == nil ? nil : "object"
    }

    struct Property: Hashable, Sendable {
        var name: String
        var schema: JSONSchema
        var isRequired: Bool
    }

    /// The named properties, required ones first, then by name.
    var properties: [Property] {
        let required = Set(value["required"]?.array?.compactMap(\.string) ?? [])
        return (value["properties"]?.object ?? [:])
            .filter { !$0.key.isEmpty }
            .sorted { lhs, rhs in
                let (l, r) = (required.contains(lhs.key), required.contains(rhs.key))
                return l != r ? l : lhs.key < rhs.key
            }
            .map { Property(name: $0.key, schema: JSONSchema($0.value), isRequired: required.contains($0.key)) }
    }

    /// What the on-device model can generate.
    indirect enum Shape: Hashable, Sendable {
        case string, number, integer, boolean
        case choice([String])
        case array(JSONSchema)
        case object([Property])
    }

    /// The schema reduced to a `Shape`. String choices (a duplicate kept once) stay choices; any other `enum`, any
    /// keyword outside the subset and anything past `maxDepth` reads as a string.
    func shape(atDepth depth: Int = 0) -> Shape {
        if depth > Self.maxDepth { return .string }
        if let values = value["enum"]?.array {
            let strings = values.compactMap(\.string)
            guard !strings.isEmpty, strings.count == values.count else { return .string }
            var seen = Set<String>()
            return .choice(strings.filter { seen.insert($0).inserted })
        }
        switch typeName {
        case "number": return .number
        case "integer": return .integer
        case "boolean": return .boolean
        case "array": return .array(JSONSchema(value["items"] ?? .object([:])))
        case "object": return .object(properties)
        default: return .string
        }
    }

    /// The root as an arguments object: its properties when it is an object, none otherwise.
    var argumentProperties: [Property] {
        if case .object(let list) = shape() { return list }
        return []
    }
}

extension JSONSchema: Codable {
    init(from decoder: any Decoder) throws {
        value = try JSONValue(from: decoder)
    }

    func encode(to encoder: any Encoder) throws {
        try value.encode(to: encoder)
    }
}
