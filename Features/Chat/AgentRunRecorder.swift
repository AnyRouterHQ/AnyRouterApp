import Foundation

/// Asks the user through `base` and tells the chat before and after, so the run is saved as waiting while the card is
/// up and the answer lands on the call's step (agent design 1.3). MCP tools ask through it too.
struct RunRecordingApprover: ToolApproving {
    let base: any ToolApproving
    /// Answers given before a relaunch, by call id: an approved call that runs again is not asked again.
    let decided: [String: ToolDecision]
    let asking: @MainActor @Sendable (ToolApprovalRequest) -> Void
    let answered: @MainActor @Sendable (ToolApprovalRequest, ToolDecision) -> Void

    func decide(_ request: ToolApprovalRequest) async -> ToolDecision {
        if let decision = decided[request.call.id] { return decision }
        await asking(request)
        let decision = await base.decide(request)
        await answered(request, decision)
        return decision
    }
}

/// The chat's tool host for one run: `base` does the work, each round the loop announces goes to the chat to save, and
/// the chat's notes are what a long run repeats.
struct RunRecordingHost: ToolHost {
    let base: any ToolHost
    let round: @MainActor @Sendable (String, [ToolCall]) -> Void
    let recite: @MainActor @Sendable () -> String?

    var specs: [ToolSpec] { base.specs }

    func execute(_ call: ToolCall) async -> ToolResult { await base.execute(call) }

    func sourceID(forTool name: String) -> String? { base.sourceID(forTool: name) }

    func willRun(_ text: String, calls: [ToolCall]) async { await round(text, calls) }

    func recitation() async -> String? { await recite() }
}
