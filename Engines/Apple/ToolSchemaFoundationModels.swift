import FoundationModels

extension ToolSchemaNode {
    /// The same shape as a dynamic schema. Names of nested objects and choices are built from the
    /// path so they stay unique inside one schema.
    func dynamicSchema(name: String) -> DynamicGenerationSchema {
        switch kind {
        case .string: return DynamicGenerationSchema(type: String.self, guides: [])
        case .number: return DynamicGenerationSchema(type: Double.self, guides: [])
        case .integer: return DynamicGenerationSchema(type: Int.self, guides: [])
        case .boolean: return DynamicGenerationSchema(type: Bool.self, guides: [])
        case .choice(let values):
            return DynamicGenerationSchema(name: name, description: description, anyOf: values)
        case .array(let element):
            return DynamicGenerationSchema(
                arrayOf: element.dynamicSchema(name: name + "_item"),
                minimumElements: nil, maximumElements: nil)
        case .object(let properties):
            return DynamicGenerationSchema(
                name: name, description: description,
                properties: properties.map { property in
                    DynamicGenerationSchema.Property(
                        name: property.name,
                        description: property.node.description,
                        schema: property.node.dynamicSchema(name: name + "_" + property.name),
                        isOptional: !property.isRequired)
                })
        }
    }

    func generationSchema(name: String) throws -> GenerationSchema {
        try GenerationSchema(root: dynamicSchema(name: name), dependencies: [])
    }
}
