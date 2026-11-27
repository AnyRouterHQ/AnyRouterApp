import Foundation

/// How an on-device model writes a tool call, and how the app asks for one. llama.cpp and MLX only generate text, so the
/// app describes the tools in the system prompt in the form the model was trained on and reads the calls back out of
/// the text (`LocalToolParser`). A model family with no entry here gets no tools.
enum LocalToolFormat: String, CaseIterable, Sendable {
    /// Qwen and other Hermes-style models: `<tool_call>{"name": ..., "arguments": {...}}</tool_call>`.
    case qwen
    /// Llama 3.1 and later: a bare JSON object, `{"name": ..., "parameters": {...}}`, after an optional `<|python_tag|>`.
    case llama
    /// Gemma: a Python call in a `tool_code` block, `tool_name(argument="value")`.
    case gemma

    /// The format for a downloaded model, from its repo or file name. Nil for models that are not local or whose family
    /// has no format here.
    static func detect(for model: ModelDescriptor) -> LocalToolFormat? {
        guard model.source == .gguf || model.source == .mlx else { return nil }
        let name = (model.id + " " + model.displayName).lowercased()
        if name.contains("qwen") { return .qwen }
        if name.contains("gemma") { return .gemma }
        if name.range(of: "llama[-_ ]?3", options: .regularExpression) != nil { return .llama }
        return nil
    }

    // MARK: Asking

    /// Added after the system prompt: the tools and the way to call one.
    func instructions(for specs: [ToolSpec]) -> String {
        switch self {
        case .qwen:
            return """
            # Tools
            You may call one or more functions to help with the user's request. The functions are described inside <tools></tools>:
            <tools>
            \(specs.map(Self.declaration).joined(separator: "\n"))
            </tools>
            To call a function, answer with a JSON object inside <tool_call></tool_call> tags and nothing else:
            <tool_call>
            {"name": <function-name>, "arguments": <arguments-json-object>}
            </tool_call>
            The result comes back inside <tool_response></tool_response>. Then answer the user in plain text.
            """
        case .llama:
            return """
            You can call tools. To call one, reply with only a JSON object in this form, with no other text:
            {"name": "<tool name>", "parameters": {"<argument name>": <value>}}
            Call one tool at a time and do not use variables. When the tool result arrives, answer in plain text.
            The tools:
            \(specs.map(Self.declaration).joined(separator: "\n"))
            """
        case .gemma:
            return """
            You can call tools. To call one, reply with only a code block like this, using keyword arguments:
            ```tool_code
            tool_name(argument="value")
            ```
            The result comes back in a tool_output block. Then answer in plain text. The tools, as Python functions:
            \(specs.map(Self.pythonSignature).joined(separator: "\n"))
            """
        }
    }

    /// The user turn that hands the results back, one block per call.
    func resultMessage(_ results: [(name: String, text: String)]) -> String {
        switch self {
        case .qwen: results.map { "<tool_response>\n\($0.text)\n</tool_response>" }.joined(separator: "\n")
        case .llama: results.map { "The tool \($0.name) returned:\n\($0.text)" }.joined(separator: "\n\n")
        case .gemma: results.map { "```tool_output\n\($0.text)\n```" }.joined(separator: "\n")
        }
    }

    /// One tool as the JSON function description Hermes and Llama models were trained on.
    private static func declaration(_ spec: ToolSpec) -> String {
        let schema = JSONValue.parse(spec.inputSchemaJSON) ?? .object(["type": .string("object")])
        let function: JSONValue = .object([
            "name": .string(spec.name), "description": .string(spec.description), "parameters": schema,
        ])
        return JSONValue.object(["type": .string("function"), "function": function]).jsonString()
    }

    /// `def name(a: str, b: int = None) -> str:` with the description as the docstring. Required arguments come first.
    private static func pythonSignature(_ spec: ToolSpec) -> String {
        let schema = JSONValue.parse(spec.inputSchemaJSON)
        let properties = schema?["properties"]?.object ?? [:]
        let required = Set(schema?["required"]?.array?.compactMap(\.string) ?? [])
        let names = properties.keys.sorted { lhs, rhs in
            required.contains(lhs) != required.contains(rhs) ? required.contains(lhs) : lhs < rhs
        }
        let arguments = names.map { name -> String in
            let kind = pythonType(properties[name]?["type"]?.string)
            return required.contains(name) ? "\(name): \(kind)" : "\(name): \(kind) = None"
        }
        return "def \(spec.name)(\(arguments.joined(separator: ", "))) -> str:\n    \"\"\"\(spec.description)\"\"\""
    }

    private static func pythonType(_ jsonType: String?) -> String {
        switch jsonType {
        case "integer": "int"
        case "number": "float"
        case "boolean": "bool"
        case "array": "list"
        case "object": "dict"
        default: "str"
        }
    }
}
