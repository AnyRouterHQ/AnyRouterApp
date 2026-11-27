import Foundation
import Testing
@testable import AnyRouter

/// PLAN LA1: a built-in tool's side-effect class decides whether the host asks. Writes and external calls ask every
/// time and can never be "always allowed"; reads run unasked; a write that shows Undo on the reply runs unasked.
struct ToolSideEffectTests {
    private struct Effect: BuiltInTool {
        let name: String
        let sideEffect: ToolSideEffect
        var undoesInsteadOfAsking = false
        let title = "Effect", summary = "", description = "", inputSchemaJSON = "{}"
        func run(_ arguments: JSONValue) async throws -> String { "ran" }
    }

    private final class Approver: ToolApproving, @unchecked Sendable {
        private let lock = NSLock()
        private var asked: [ToolApprovalRequest] = []
        private let decision: ToolDecision
        init(_ decision: ToolDecision) { self.decision = decision }
        var requests: [ToolApprovalRequest] { lock.withLock { asked } }
        func decide(_ request: ToolApprovalRequest) async -> ToolDecision {
            lock.withLock { asked.append(request) }
            return decision
        }
    }

    private func run(_ tool: Effect, approver: Approver?) async -> ToolResult {
        let host = AgentToolHost(builtIns: [tool], search: nil, mcp: nil, approver: approver)
        return await host.execute(ToolCall(id: "c", name: tool.name, argumentsJSON: "{}"))
    }

    @Test func readsRunWithoutAsking() async {
        for effect in [ToolSideEffect.read, .sensitiveRead] {
            let approver = Approver(.deny)
            #expect(await run(Effect(name: "t", sideEffect: effect), approver: approver).text == "ran")
            #expect(approver.requests.isEmpty)
        }
    }

    @Test func writesAndExternalCallsAskEveryTimeAndNeverOfferAlwaysAllow() async {
        let cases: [(ToolSideEffect, String)] = [(.write, "This changes data in the app."), (.external, "This sends something outside the app.")]
        for (effect, reason) in cases {
            let approver = Approver(.alwaysAllow)
            let tool = Effect(name: "t", sideEffect: effect)
            let host = AgentToolHost(builtIns: [tool], search: nil, mcp: nil, approver: approver)
            for _ in 0..<2 {
                #expect(await host.execute(ToolCall(id: "c", name: "t", argumentsJSON: "{}")).text == "ran")
            }
            #expect(approver.requests.count == 2, "an Always allow answer is not remembered")
            let request = approver.requests[0]
            #expect(request.reason == reason && !request.canRemember, "a reason keeps Always allow off the card")
            #expect(request.serverName == "This device" && request.spec.sideEffect == effect)
        }
    }

    @Test func aDeniedOrUnaskableWriteNeverRuns() async {
        let tool = Effect(name: "t", sideEffect: .write)
        let denied = await run(tool, approver: Approver(.deny))
        #expect(denied == ToolResult(callID: "c", name: "t", text: ToolResult.deniedText, isError: true))
        #expect(await run(tool, approver: nil).text == ToolResult.deniedText)
    }

    @Test func aWriteThatShowsUndoRunsWithoutAsking() async {
        let approver = Approver(.deny)
        #expect(await run(Effect(name: "t", sideEffect: .write, undoesInsteadOfAsking: true), approver: approver).text == "ran")
        #expect(approver.requests.isEmpty)
    }

    @Test func specsCarryTheClassAndReadOnlyFollowsIt() {
        #expect(Effect(name: "t", sideEffect: .sensitiveRead).spec.sideEffect == .sensitiveRead)
        #expect(ToolSideEffect.allCases.filter(\.isRead) == [.read, .sensitiveRead])
        let marked = ToolSpec(name: "a", title: nil, description: "", inputSchemaJSON: "{}", isReadOnly: true)
        let unmarked = ToolSpec(name: "b", title: nil, description: "", inputSchemaJSON: "{}", isReadOnly: false)
        #expect(marked.sideEffect == .read && marked.isReadOnly)
        #expect(unmarked.sideEffect == .external && !unmarked.isReadOnly, "an MCP tool not marked read-only acts on its server")
    }
}
