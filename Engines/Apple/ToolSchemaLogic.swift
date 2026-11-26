import Foundation

/// A tool's JSON Schema reduced to what the on-device model can generate: strings, numbers,
/// integers, booleans, string choices, arrays and objects. Anything else degrades to a string.
/// Kept free of FoundationModels so the mapping is testable anywhere.
struct ToolSchemaNode: Equatable, Sendable {
    struct Property: Equatable, Sendable {
        var name: String
        var node: ToolSchemaNode
        var isRequired: Bool
    }

    indirect enum Kind: Equatable, Sendable {
        case string, number, integer, boolean
        case choice([String])
        case array(ToolSchemaNode)
        case object([Property])
    }

    var kind: Kind
    var description: String?

    /// Nesting deeper than this becomes a string, which keeps the schema small for a small context.
    static let maxDepth = 5

    /// The arguments schema of a tool. Invalid JSON or a non-object root gives an object with no properties.
    static func parse(_ json: String) -> ToolSchemaNode {
        guard let data = json.data(using: .utf8),
            let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return ToolSchemaNode(kind: .object([]), description: nil) }
        let node = node(from: root, depth: 0)
        if case .object = node.kind { return node }
        return ToolSchemaNode(kind: .object([]), description: node.description)
    }

    private static func node(from schema: [String: Any], depth: Int) -> ToolSchemaNode {
        let text = (schema["description"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        func make(_ kind: Kind) -> ToolSchemaNode { ToolSchemaNode(kind: kind, description: text) }
        if depth > maxDepth { return make(.string) }

        if let values = schema["enum"] as? [Any] {
            let strings = values.compactMap { $0 as? String }
            guard !strings.isEmpty, strings.count == values.count else { return make(.string) }
            var seen = Set<String>()
            return make(.choice(strings.filter { seen.insert($0).inserted }))
        }

        switch typeName(of: schema) {
        case "string": return make(.string)
        case "number": return make(.number)
        case "integer": return make(.integer)
        case "boolean": return make(.boolean)
        case "array":
            let items = schema["items"] as? [String: Any]
            let element = node(from: items ?? [:], depth: depth + 1)
            return make(.array(element))
        case "object":
            let properties = schema["properties"] as? [String: Any] ?? [:]
            let required = Set(schema["required"] as? [String] ?? [])
            let list = properties.keys
                .filter { !$0.isEmpty }
                .sorted { lhs, rhs in
                    let l = required.contains(lhs), r = required.contains(rhs)
                    return l != r ? l : lhs < rhs
                }
                .map { name in
                    Property(
                        name: name,
                        node: node(from: properties[name] as? [String: Any] ?? [:], depth: depth + 1),
                        isRequired: required.contains(name))
                }
            return make(.object(list))
        default:
            return make(.string)
        }
    }

    /// `type` may be a list such as `["string", "null"]`: take the first entry that is not null.
    private static func typeName(of schema: [String: Any]) -> String? {
        if let type = schema["type"] as? String { return type }
        if let types = schema["type"] as? [Any],
            let first = types.compactMap({ $0 as? String }).first(where: { $0 != "null" })
        {
            return first
        }
        return schema["properties"] is [String: Any] ? "object" : nil
    }
}
