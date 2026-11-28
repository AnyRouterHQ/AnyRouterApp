import Foundation

/// One tool round of a run: what the model wrote, the calls it asked for, and the answer to each, in the same order.
struct AgentRound: Equatable, Sendable {
    /// The round's text as the model wrote it, with its calls when it writes them inline.
    var text: String
    var calls: [ToolCall]
    var results: [ToolResult]
}

/// Where a run stopped, to go on from (agent design 1.3): the rounds that finished, and the round whose calls were
/// running. The loop starts at `act` with the first call of `pending` that has no result.
struct AgentResume: Equatable, Sendable {
    var rounds: [AgentRound]
    var pending: AgentRound
}

/// An engine that runs on `AgentLoop` and can go on from a saved run.
protocol ResumableEngine: ChatEngine {
    /// Same as `stream(model:messages:params:tools:)`, from `resuming` when it is set.
    func stream(model: ModelDescriptor, messages: [ChatMessage], params: GenerationParams, tools: (any ToolHost)?, resuming: AgentResume?)
        -> AsyncThrowingStream<ChatDelta, Error>
}

/// What one model round streams (agent design 1.4).
enum StepEvent: Equatable, Sendable {
    /// Text to show.
    case text(String)
    /// The round's whole text for the next request, when it is not the text shown (calls written inline).
    case wrote(String)
    case reasoning(String)
    /// A call the model asked for. The loop decides whether it runs.
    case proposed(ToolCall)
    case usage(prompt: Int, completion: Int)
    case metadata(ResponseMetadata)
    case end(finishReason: String?)
}

/// One model round of an engine. The engine streams text and proposes calls; `AgentLoop` runs them.
protocol StepFunction: Sendable {
    /// The run's room for tool results; nil when the window is unknown and nothing is cut or cleared.
    var budget: RunBudgetLogic.Budget? { get }
    /// Tokens the request for the round after `rounds` would hold.
    func tokens(_ rounds: [AgentRound], toolsOn: Bool) -> Int
    /// The round after `rounds`. With `toolsOn` false the model is asked to answer without tools.
    func step(_ rounds: [AgentRound], toolsOn: Bool) -> AsyncThrowingStream<StepEvent, Error>
}

/// The app's one tool loop for every engine but Apple's (PLAN D28, agent design 1.2 and 3.4). It walks `AgentGraph`:
/// asks the engine for one round at a time, runs the proposed calls through the `ToolHost` inside a `ToolRunScope`, and
/// keeps the results inside the window with `RunBudgetLogic`. It streams what engines stream: text and reasoning as they
/// come, `.toolCall` before each call runs and `.toolResult` after it, then the metadata and the usage of all rounds,
/// then `.done`. The round after `maxToolRounds` tool rounds, or after the model repeats a call that failed, has tools off.
enum AgentLoop {
    /// What the model reads when it repeats a call that already failed (agent design E5). The call does not run again.
    static let repeatedFailureText = "This exact call already failed, so it was not run again. Answer with what you have."

    /// With `resume` the run goes on from where it stopped instead of asking the model first.
    static func stream(
        step: some StepFunction, host: (any ToolHost)?, maxToolRounds: Int, resume: AgentResume? = nil
    ) -> AsyncThrowingStream<ChatDelta, Error> {
        AsyncThrowingStream { continuation in
            let scope = ToolRunScope()
            let task = Task {
                do {
                    try await run(step: step, host: host, maxToolRounds: maxToolRounds, resume: resume, scope: scope) {
                        _ = continuation.yield($0)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
                scope.cancelAll()
            }
        }
    }

    private static func run(
        step: some StepFunction, host: (any ToolHost)?, maxToolRounds: Int, resume: AgentResume?, scope: ToolRunScope,
        emit: @escaping @Sendable (ChatDelta) -> Void
    ) async throws {
        var rounds: [AgentRound] = resume?.rounds ?? []
        var sent = rounds
        var proposed = resume?.pending ?? AgentRound(text: "", calls: [], results: [])
        var maxRounds = host == nil ? 0 : maxToolRounds
        var stubbed = 0
        var failed: Set<[String]> = []
        var usage: (prompt: Int, completion: Int)?
        var metadata: ResponseMetadata?
        var finishReason: String?
        var node = resume == nil ? AgentNode.assemble : .act
        while node != .finish {
            switch node {
            case .assemble:
                let toolsOn = rounds.count < maxRounds
                if let budget = step.budget {
                    let kept = cleared(rounds, stubbed: stubbed, budget: budget) { step.tokens($0, toolsOn: toolsOn) }
                    sent = kept.rounds
                    stubbed = kept.stubbed
                } else {
                    sent = rounds
                }
                node = AgentGraph.next(node, on: .fits, round: rounds.count, maxRounds: maxRounds)
            case .generate:
                proposed = AgentRound(text: "", calls: [], results: [])
                var wrote: String?
                for try await event in step.step(sent, toolsOn: rounds.count < maxRounds) {
                    switch event {
                    case .text(let piece):
                        proposed.text += piece
                        emit(.text(piece))
                    case .wrote(let text): wrote = text
                    case .reasoning(let piece): emit(.reasoning(piece))
                    case .proposed(let call): proposed.calls.append(call)
                    case .usage(let prompt, let completion):
                        usage = ((usage?.prompt ?? 0) + prompt, (usage?.completion ?? 0) + completion)
                    case .metadata(let next): metadata = ResponseMetadata.combining(metadata, next)
                    case .end(let reason): finishReason = reason
                    }
                }
                try Task.checkCancellation()
                if let wrote { proposed.text = wrote }
                node = AgentGraph.next(node, on: proposed.calls.isEmpty ? .noCalls : .calls, round: rounds.count, maxRounds: maxRounds)
                if node == .act { await host?.willRun(proposed.text, calls: proposed.calls) }
            case .act:
                guard let host else {
                    node = .finish
                    break
                }
                var round = proposed
                // A resumed round already holds the results of the calls that ran before the app closed.
                for call in round.calls.dropFirst(round.results.count) {
                    try Task.checkCancellation()
                    let key = [call.name, call.argumentsJSON]
                    if failed.contains(key) {
                        round.results.append(ToolResult(callID: call.id, name: call.name, text: repeatedFailureText, isError: true))
                        maxRounds = min(maxRounds, rounds.count + 1)
                        continue
                    }
                    let outcome = Outcome()
                    _ = await scope.run(
                        name: call.name, argumentsJSON: call.argumentsJSON, host: host,
                        emit: { delta in
                            outcome.keep(delta)
                            emit(delta)
                        },
                        makeID: { call.id })
                    let result = outcome.result(for: call)
                    if result.isError { failed.insert(key) }
                    round.results.append(result)
                }
                try Task.checkCancellation()
                if let budget = step.budget, budget.onDevice {
                    // Each answer gets a share of what is left after this round's own text.
                    let left = budget.limit - step.tokens(sent + [AgentRound(text: round.text, calls: [], results: [])], toolsOn: true)
                    let cap = RunBudgetLogic.resultCap(window: budget.window, left: left)
                    for index in round.results.indices {
                        round.results[index].text = RunBudgetLogic.clip(round.results[index].text, tokens: cap)
                    }
                }
                rounds.append(round)
                node = AgentGraph.next(node, on: .resultsIn, round: rounds.count, maxRounds: maxRounds)
            case .compact, .approve, .finish, .remember:
                // Compaction runs before the reply and approval inside the host, so the loop never reaches these yet.
                node = .finish
            }
        }
        if let metadata { emit(.metadata(metadata)) }
        if let usage { emit(.usage(prompt: usage.prompt, completion: usage.completion)) }
        emit(.done(finishReason: finishReason))
    }

    /// A run whose engine keeps its own loop (Apple's) goes on as a new turn (agent design 1.3, Apple row): the calls
    /// that have no result run through the host, then the engine is asked again with the earlier text and every result
    /// as text, since its framework loop cannot be entered again.
    static func continuing(
        engine: any ChatEngine, model: ModelDescriptor, messages: [ChatMessage], params: GenerationParams,
        host: (any ToolHost)?, text: String, done: [ToolResult], calls: [ToolCall]
    ) -> AsyncThrowingStream<ChatDelta, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var results = done
                if let host {
                    for call in calls {
                        continuation.yield(.toolCall(call))
                        let result = await host.execute(call)
                        continuation.yield(.toolResult(result))
                        results.append(result)
                    }
                }
                do {
                    try Task.checkCancellation()
                    var turn = messages
                    if !text.isEmpty { turn.append(ChatMessage(role: .assistant, content: text)) }
                    turn.append(ChatMessage(role: .user, content: continuationText(results)))
                    for try await delta in engine.stream(model: model, messages: turn, params: params, tools: host) {
                        continuation.yield(delta)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The tool results of a run that goes on as a new turn, as the user message of that turn.
    static func continuationText(_ results: [ToolResult]) -> String {
        let lines = results.map { "\($0.name): \(ToolRunScope.modelText(for: $0))" }
        return (["Your tool calls answered:"] + lines + ["Go on with your answer."]).joined(separator: "\n")
    }

    /// The rounds as the next request carries them. A device run clears old results until they fit; a cloud run
    /// stubs more only in large steps, starting from the `stubbed` it sent last.
    private static func cleared(
        _ rounds: [AgentRound], stubbed: Int, budget: RunBudgetLogic.Budget, tokens: ([AgentRound]) -> Int
    ) -> (rounds: [AgentRound], stubbed: Int) {
        let results = rounds.map { round in
            zip(round.calls, round.results).map { RunBudgetLogic.Result(name: $0.name, argumentsJSON: $0.argumentsJSON, text: $1.text) }
        }
        func applying(_ texts: [[RunBudgetLogic.Result]]) -> [AgentRound] {
            zip(rounds, texts).map { round, texts in
                var round = round
                for (index, text) in texts.enumerated() { round.results[index].text = text.text }
                return round
            }
        }
        if budget.onDevice {
            return (applying(RunBudgetLogic.cleared(results) { tokens(applying($0)) <= budget.limit }), stubbed)
        }
        let count = RunBudgetLogic.cloudStubs(results, sent: stubbed, limit: budget.limit) { tokens(applying($0)) }
        return (applying(RunBudgetLogic.stubbing(results, oldest: count)), count)
    }
}

/// The result `ToolRunScope` emitted for one call.
private final class Outcome: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: ToolResult?

    func keep(_ delta: ChatDelta) {
        if case .toolResult(let result) = delta { lock.withLock { stored = result } }
    }

    /// The scope emits a result for every call it runs, cancelled ones included.
    func result(for call: ToolCall) -> ToolResult {
        lock.withLock { stored } ?? ToolResult(callID: call.id, name: call.name, text: "The tool call was cancelled.", isError: true)
    }
}
