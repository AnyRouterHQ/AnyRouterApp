import Foundation
import Testing
@testable import AnyRouter

/// Agent v2 K1a: a tool's schema is kept whole (MCP servers send anything) and always written with sorted keys, so the
/// bytes a request carries do not change from run to run; the typed readers cover only the app's own subset.
struct JSONSchemaTests {
    private let mcp = #"{"type":"object","required":["q"],"properties":{"q":{"anyOf":[{"type":"string"},{"type":"null"}]},"n":{"type":"integer","minimum":1,"maximum":10}},"additionalProperties":false}"#

    @Test func aSchemaRoundTripsWholeWithSortedKeys() throws {
        let schema = JSONSchema(parsing: mcp)
        #expect(schema.json == #"{"additionalProperties":false,"properties":{"n":{"maximum":10,"minimum":1,"type":"integer"},"q":{"anyOf":[{"type":"string"},{"type":"null"}]}},"required":["q"],"type":"object"}"#)
        let encoded = try JSONEncoder().encode(schema)
        let decoded = try JSONDecoder().decode(JSONSchema.self, from: encoded)
        #expect(decoded == schema)
        #expect(decoded.json == schema.json, "the same bytes after a round trip")
        #expect(JSONSchema(parsing: #"{"b":1,"a":2}"#).json == JSONSchema(parsing: #"{"a":2,"b":1}"#).json, "key order never matters")
    }

    @Test func aLiteralAndTextThatIsNotJSON() {
        let literal: JSONSchema = #"{"type":"object"}"#
        #expect(literal.value == .object(["type": .string("object")]))
        #expect(JSONSchema(parsing: "not json").value == JSONSchema.noArguments)
    }

    @Test func aSchemaThatIsNotAnObjectGoesOutAsNoArguments() {
        #expect(JSONSchema(.array([])).wireObject == JSONSchema.noArguments)
        #expect(JSONSchema(parsing: mcp).wireObject == JSONSchema(parsing: mcp).value)
    }

    @Test func theReadersCoverTheSubset() {
        let schema = JSONSchema(parsing: mcp)
        #expect(schema.typeName == "object")
        #expect(schema.properties.map(\.name) == ["q", "n"], "required first")
        #expect(schema.properties.first?.schema.shape() == .string, "anyOf reads as a string, and stays whole in value")
        #expect(schema.properties.last?.schema.shape() == .integer)
        #expect(JSONSchema(parsing: #"{"properties":{"a":{}}}"#).typeName == "object")
        #expect(JSONSchema(parsing: #"{"type":["null","boolean"]}"#).shape() == .boolean)
        #expect(JSONSchema(parsing: #"{"type":["null"]}"#).typeName == nil)
        #expect(JSONSchema(parsing: #"{"description":""}"#).description == nil)
        #expect(JSONSchema(parsing: #"{"type":"string"}"#).argumentProperties.isEmpty)
    }
}
