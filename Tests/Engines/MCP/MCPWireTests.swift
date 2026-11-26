import Foundation
import Testing
@testable import AnyRouter

struct MCPWireTests {
    @Test func aResponseIdOrErrorCodeOutsideIntRangeIsNotAnAnswerAndDoesNotTrap() throws {
        let hostile: [JSONValue] = [
            .object(["id": .number(1e300), "result": .object([:])]),
            .object(["id": .number(.infinity), "result": .object([:])]),
            .object(["id": .number(1.5), "result": .object([:])]),
        ]
        #expect(throws: MCPError.invalidResponse("No answer for request 1.")) {
            _ = try MCPWire.result(id: 1, in: hostile)
        }
        let badCode: [JSONValue] = [.object(["id": .number(1), "error": .object(["code": .number(1e300), "message": .string("x")])])]
        #expect(throws: MCPError.rpc(code: 0, message: "x")) { _ = try MCPWire.result(id: 1, in: badCode) }
    }
}
