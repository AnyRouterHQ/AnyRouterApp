import Foundation

/// An engine whose cloud model can run a subagent: the same model in a loop of its own, with its own messages and tools
/// (PLAN D28 S1). Device engines never do: one resident local model would queue behind its parent, and a cloud subagent
/// would send a device chat's text off the device.
protocol SubagentEngine: ChatEngine {
    func childStep(model: ModelDescriptor, messages: [ChatMessage], params: GenerationParams, specs: [ToolSpec]) -> any StepFunction
}

/// The chat's tools plus `delegate_task`, which hands one research task to a subagent and answers with its summary.
struct SubagentHost: ToolHost {
    let base: any ToolHost
    let runner: SubagentRunner

    var specs: [ToolSpec] { base.specs.filter { $0.name != SubagentLogic.toolName } + [SubagentLogic.spec] }

    func execute(_ call: ToolCall) async -> ToolResult {
        if call.name == SubagentLogic.toolName { return await runner.run(call) }
        return await base.execute(call)
    }

    func sourceID(forTool name: String) -> String? {
        name == SubagentLogic.toolName ? ToolSourceCatalog.anyRouter.id : base.sourceID(forTool: name)
    }

    func willRun(_ text: String, calls: [ToolCall]) async { await base.willRun(text, calls: calls) }

    func recitation() async -> String? { await base.recitation() }
}

/// A subagent's tools: only those `SubagentLogic.childToolNames` lists. A call to any other tool is refused.
struct SubagentToolHost: ToolHost {
    let base: any ToolHost

    var specs: [ToolSpec] { base.specs.filter { SubagentLogic.childToolNames.contains($0.name) } }

    func execute(_ call: ToolCall) async -> ToolResult {
        guard specs.contains(where: { $0.name == call.name }) else {
            return ToolResult(callID: call.id, name: call.name, text: "Unknown tool: \(call.name).", isError: true)
        }
        return await base.execute(call)
    }

    func sourceID(forTool name: String) -> String? { base.sourceID(forTool: name) }
}

/// Runs one subagent on `AgentLoop`: the task is its only message, it has the read tools, at most
/// `SubagentLogic.maxRounds` requests and `SubagentLogic.tokenBudget` tokens. Its calls go to `onSteps` as they
/// happen, for the row of the call that started it; its cost and tokens come back on the result. Stopping the parent
/// cancels the call, which ends the subagent's stream and with it the subagent.
struct SubagentRunner: Sendable {
    let makeStep: @Sendable (_ messages: [ChatMessage], _ specs: [ToolSpec]) -> any StepFunction
    let tools: SubagentToolHost?
    let onSteps: @MainActor @Sendable (ToolCall, [ToolStep]) -> Void

    func run(_ call: ToolCall) async -> ToolResult {
        func failure(_ text: String) -> ToolResult { ToolResult(callID: call.id, name: call.name, text: text, isError: true) }
        guard let message = SubagentLogic.message(from: call.argumentsJSON) else { return failure(SubagentLogic.missingTaskText) }
        let step = makeStep([ChatMessage(role: .user, content: message)], tools?.specs ?? [])
        var steps: [ToolStep] = []
        var summary = ""
        var metadata: ResponseMetadata?
        var usage: (prompt: Int, completion: Int)?
        do {
            let stream = AgentLoop.stream(
                step: step, host: tools, maxToolRounds: SubagentLogic.maxRounds - 1, tokenBudget: SubagentLogic.tokenBudget)
            for try await delta in stream {
                switch delta {
                case .text(let piece): summary += piece
                case .toolCall(let next):
                    // Text before a call belongs to that round; the summary is what the last round writes.
                    summary = ""
                    steps.append(ToolStep(call: next, result: nil, sourceID: tools?.sourceID(forTool: next.name)))
                    await onSteps(call, steps)
                case .toolResult(let result):
                    if let index = steps.firstIndex(where: { $0.id == result.callID }) { steps[index].result = result }
                    await onSteps(call, steps)
                case .usage(let prompt, let completion): usage = (prompt, completion)
                case .metadata(let next): metadata = next
                case .reasoning, .done: break
                }
            }
        } catch {
            return failure(error.localizedDescription)
        }
        if Task.isCancelled { return failure(ToolRowLogic.cancelledText) }
        var result = failure(SubagentLogic.noSummaryText)
        if let answer = SubagentLogic.answer(summary, steps: steps) {
            result.text = answer
            result.isError = false
        }
        result.costUSD = metadata?.costUSD
        result.promptTokens = metadata?.promptTokens ?? usage?.prompt
        result.completionTokens = metadata?.completionTokens ?? usage?.completion
        return result
    }
}
