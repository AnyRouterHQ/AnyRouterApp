import FoundationModels

extension JSONSchema {
    /// The schema as a dynamic generation schema, reduced by `shape(atDepth:)`. Names of nested objects and choices are
    /// built from the path so they stay unique inside one schema.
    func dynamicSchema(name: String, depth: Int = 0) -> DynamicGenerationSchema {
        switch shape(atDepth: depth) {
        case .string: return DynamicGenerationSchema(type: String.self, guides: [])
        case .number: return DynamicGenerationSchema(type: Double.self, guides: [])
        case .integer: return DynamicGenerationSchema(type: Int.self, guides: [])
        case .boolean: return DynamicGenerationSchema(type: Bool.self, guides: [])
        case .choice(let values):
            return DynamicGenerationSchema(name: name, description: description, anyOf: values)
        case .array(let element):
            return DynamicGenerationSchema(
                arrayOf: element.dynamicSchema(name: name + "_item", depth: depth + 1),
                minimumElements: nil, maximumElements: nil)
        case .object(let properties):
            return object(name: name, properties: properties, depth: depth)
        }
    }

    /// The tool's arguments: the root is always an object, with no properties when the schema is not one.
    func generationSchema(name: String) throws -> GenerationSchema {
        try GenerationSchema(root: object(name: name, properties: argumentProperties, depth: 0), dependencies: [])
    }

    private func object(name: String, properties: [Property], depth: Int) -> DynamicGenerationSchema {
        DynamicGenerationSchema(
            name: name, description: description,
            properties: properties.map { property in
                DynamicGenerationSchema.Property(
                    name: property.name,
                    description: property.schema.description,
                    schema: property.schema.dynamicSchema(name: name + "_" + property.name, depth: depth + 1),
                    isOptional: !property.isRequired)
            })
    }
}
