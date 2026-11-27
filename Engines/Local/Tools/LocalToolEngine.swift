import Foundation

/// Gives a local engine (llama.cpp or MLX) a tool loop. The engines only generate text, so this wraps one: it adds the
/// tools to the system prompt in the model's own format, reads calls out of the streamed text, runs them through the same
/// `ToolHost` and `ToolRunScope` every other engine uses, and asks again with the results, up to `maxRounds` times.
/// A model counts as tool-capable only when `isEnabled` says so and its family has a `LocalToolFormat`.
struct LocalToolEngine: ChatEngine {
    /// Most generations one reply may take. The last one is asked to answer without tools.
    static let maxRounds = 4

    let base: any ChatEngine
    /// The person's switch for tools on this device's models. Read each time models are listed and each time a reply starts.
    let isEnabled: @Sendable () -> Bool
    let makeID: @Sendable () -> String

    init(wrapping base: any ChatEngine, isEnabled: @escaping @Sendable () -> Bool, makeID: @escaping @Sendable () -> String = { UUID().uuidString }) {
        self.base = base
        self.isEnabled = isEnabled
        self.makeID = makeID
    }

    var source: ModelSource { base.source }

    func availableModels() async throws -> [ModelDescriptor] {
        let models = try await base.availableModels()
        guard isEnabled() else { return models }
        return models.map { model in
            guard LocalToolFormat.detect(for: model) != nil else { return model }
            var withTools = model
            withTools.capabilities.insert("tools")
            return withTools
        }
    }

    func stream(model: ModelDescriptor, messages: [ChatMessage], params: GenerationParams) -> AsyncThrowingStream<ChatDelta, Error> {
        base.stream(model: model, messages: messages, params: params)
    }

    func stream(model: ModelDescriptor, messages: [ChatMessage], params: GenerationParams, tools: (any ToolHost)?)
        -> AsyncThrowingStream<ChatDelta, Error> {
        guard let host = tools, !host.specs.isEmpty, isEnabled(), let format = LocalToolFormat.detect(for: model) else {
            return base.stream(model: model, messages: messages, params: params)
        }
        let (base, makeID) = (self.base, self.makeID)
        return AsyncThrowingStream { continuation in
            let scope = ToolRunScope()
            let task = Task {
                do {
                    try await Self.run(
                        base: base, model: model, messages: messages, params: params, host: host, format: format,
                        scope: scope, makeID: makeID, continuation: continuation)
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
        base: any ChatEngine, model: ModelDescriptor, messages: [ChatMessage], params: GenerationParams,
        host: any ToolHost, format: LocalToolFormat, scope: ToolRunScope, makeID: @escaping @Sendable () -> String,
        continuation: AsyncThrowingStream<ChatDelta, Error>.Continuation
    ) async throws {
        // The window this run must fit (agent design 3.4): what the device runs, less room for the answer.
        let window = CompactionLogic.window(for: model) ?? 4096
        let limit = window - RunBudgetLogic.reserve(window: window)
        var rounds: [(raw: String, results: [RunBudgetLogic.Result])] = []
        func transcript(_ results: [[RunBudgetLogic.Result]]) -> [ChatMessage] {
            messages + zip(rounds, results).flatMap { round, answers in
                [ChatMessage(role: .assistant, content: round.raw),
                 ChatMessage(role: .user, content: format.resultMessage(answers.map { ($0.name, $0.text) }))]
            }
        }
        func used(_ sent: [ChatMessage], system: String?) -> Int {
            sent.reduce(system.map(TokenCountLogic.estimate) ?? 0) { $0 + TokenCountLogic.estimate($1.content) + PromptAssembler.perMessageTokens }
        }
        var usage: (prompt: Int, completion: Int)?
        var finishReason: String?
        for round in 0..<maxRounds {
            let lastRound = round == maxRounds - 1
            var roundParams = params
            if !lastRound {
                let guide = format.instructions(for: host.specs)
                roundParams.systemPrompt = [params.systemPrompt, guide].compactMap { $0 }.joined(separator: "\n\n")
            }
            let system = roundParams.systemPrompt
            let results = RunBudgetLogic.cleared(rounds.map(\.results)) { used(transcript($0), system: system) <= limit }
            let sent = transcript(results)
            var parser = LocalToolParser(format: lastRound ? nil : format)
            var raw = ""
            for try await delta in base.stream(model: model, messages: sent, params: roundParams) {
                switch delta {
                case .text(let piece):
                    raw += piece
                    let shown = parser.feed(piece)
                    if !shown.isEmpty { continuation.yield(.text(shown)) }
                case .usage(let prompt, let completion):
                    usage = ((usage?.prompt ?? 0) + prompt, (usage?.completion ?? 0) + completion)
                case .done(let reason):
                    finishReason = reason
                default:
                    continuation.yield(delta)
                }
            }
            try Task.checkCancellation()
            let end = parser.finish()
            if !end.text.isEmpty { continuation.yield(.text(end.text)) }
            guard !end.calls.isEmpty, !lastRound else { break }

            // Each answer gets a share of what is left after this round's own text.
            let left = limit - used(sent + [ChatMessage(role: .assistant, content: raw)], system: system)
            var answers: [RunBudgetLogic.Result] = []
            for call in end.calls {
                let text = await scope.run(
                    name: call.name, argumentsJSON: call.argumentsJSON, host: host,
                    emit: { _ = continuation.yield($0) }, makeID: makeID)
                let clipped = RunBudgetLogic.clip(text, tokens: RunBudgetLogic.resultCap(window: window, left: left))
                answers.append(RunBudgetLogic.Result(name: call.name, argumentsJSON: call.argumentsJSON, text: clipped))
            }
            try Task.checkCancellation()
            rounds.append((raw, answers))
        }
        if let usage { continuation.yield(.usage(prompt: usage.prompt, completion: usage.completion)) }
        continuation.yield(.done(finishReason: finishReason ?? "stop"))
    }
}
