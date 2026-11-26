import FoundationModels

/// One `ToolSpec` as a FoundationModels `Tool`. `GeneratedContent` is the arguments type, so the
/// schema comes from the spec at run time instead of a `@Generable` struct.
struct AppleDynamicTool: Tool {
    typealias Arguments = GeneratedContent
    typealias Output = String

    let name: String
    let description: String
    let parameters: GenerationSchema
    let invoke: @Sendable (String) async -> String

    func call(arguments: GeneratedContent) async throws -> String {
        await invoke(arguments.jsonString)
    }

    /// A spec whose schema the framework rejects is left out rather than offered broken.
    static func make(
        specs: [ToolSpec],
        host: any ToolHost,
        scope: ToolRunScope,
        emit: @escaping @Sendable (ChatDelta) -> Void
    ) -> [AppleDynamicTool] {
        // How many tools the model gets is decided once, by `ToolProfile`, before the host hands over its specs.
        specs.compactMap { spec -> AppleDynamicTool? in
            guard let schema = try? ToolSchemaNode.parse(spec.inputSchemaJSON).generationSchema(name: spec.name)
            else { return nil }
            return AppleDynamicTool(
                name: spec.name, description: spec.description, parameters: schema,
                invoke: { json in
                    await scope.run(name: spec.name, argumentsJSON: json, host: host, emit: emit)
                })
        }
    }
}
