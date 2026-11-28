import Foundation

/// Gives a local engine (llama.cpp or MLX) tools. The engines only generate text, so this wraps one and runs it on the
/// app's tool loop (`AgentLoop`) one generation at a time (`LocalToolStep`), up to `maxRounds` generations.
/// A model counts as tool-capable only when `isEnabled` says so and its family has a `LocalToolFormat`.
struct LocalToolEngine: ResumableEngine {
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
        stream(model: model, messages: messages, params: params, tools: tools, resuming: nil)
    }

    /// The same loop, going on from a run that stopped for approval when `resuming` is set (agent design 1.3).
    func stream(model: ModelDescriptor, messages: [ChatMessage], params: GenerationParams, tools: (any ToolHost)?, resuming: AgentResume?)
        -> AsyncThrowingStream<ChatDelta, Error> {
        guard let host = tools, !host.specs.isEmpty, isEnabled(), let format = LocalToolFormat.detect(for: model) else {
            return base.stream(model: model, messages: messages, params: params)
        }
        let step = LocalToolStep(
            base: base, model: model, messages: messages, params: params, specs: host.specs, format: format, makeID: makeID)
        return AgentLoop.stream(step: step, host: host, maxToolRounds: Self.maxRounds - 1, resume: resuming)
    }
}

/// One generation of a local model as a round of the app's tool loop (agent design 1.4). The tools go in the system
/// prompt in the family's format and `LocalToolParser` reads the calls out of the streamed text. Earlier rounds go back
/// as the model's own text and a user message with the results. With tools off there is no tool text and no format,
/// so a call the model still writes is shown, not run.
struct LocalToolStep: StepFunction {
    /// The tail of the last round, when the tools stay listed but no more calls are run.
    static let answerNow = "Answer now without tools."

    let base: any ChatEngine
    let model: ModelDescriptor
    let messages: [ChatMessage]
    let params: GenerationParams
    let specs: [ToolSpec]
    let format: LocalToolFormat
    let makeID: @Sendable () -> String

    /// What the device runs, less room for the answer (agent design 3.4).
    var budget: RunBudgetLogic.Budget? {
        RunBudgetLogic.Budget(window: CompactionLogic.window(for: model) ?? 4096, onDevice: true)
    }

    func tokens(_ rounds: [AgentRound], toolsOn: Bool) -> Int {
        let (sent, roundParams) = request(rounds, toolsOn: toolsOn)
        return sent.reduce(roundParams.systemPrompt.map(TokenCountLogic.estimate) ?? 0) {
            $0 + TokenCountLogic.estimate($1.content) + PromptAssembler.perMessageTokens
        }
    }

    func step(_ rounds: [AgentRound], toolsOn: Bool) -> AsyncThrowingStream<StepEvent, Error> {
        let (sent, roundParams) = request(rounds, toolsOn: toolsOn)
        let (base, model, makeID) = (self.base, self.model, self.makeID)
        let format: LocalToolFormat? = toolsOn ? self.format : nil
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var parser = LocalToolParser(format: format)
                    var raw = ""
                    var finishReason: String?
                    for try await delta in base.stream(model: model, messages: sent, params: roundParams) {
                        switch delta {
                        case .text(let piece):
                            raw += piece
                            let shown = parser.feed(piece)
                            if !shown.isEmpty { continuation.yield(.text(shown)) }
                        case .reasoning(let piece): continuation.yield(.reasoning(piece))
                        case .usage(let prompt, let completion): continuation.yield(.usage(prompt: prompt, completion: completion))
                        case .metadata(let metadata): continuation.yield(.metadata(metadata))
                        case .done(let reason): finishReason = reason
                        case .toolCall, .toolResult: break
                        }
                    }
                    let end = parser.finish()
                    if !end.text.isEmpty { continuation.yield(.text(end.text)) }
                    continuation.yield(.wrote(raw))
                    for call in end.calls {
                        continuation.yield(.proposed(ToolCall(id: makeID(), name: call.name, argumentsJSON: call.argumentsJSON)))
                    }
                    continuation.yield(.end(finishReason: finishReason ?? "stop"))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The messages and parameters of the round after `rounds`.
    private func request(_ rounds: [AgentRound], toolsOn: Bool) -> (messages: [ChatMessage], params: GenerationParams) {
        var roundParams = params
        // The turn's photos stay images in every round: a round's results arrive as a user message without them.
        roundParams.imagesFrom = params.imagesFrom ?? messages.last(where: { $0.role == .user })?.id
        // The tool text stays in every round, the last one too, so the start of the prompt never changes inside a run
        // and a kept cache stays valid (agent v2 U9). The last round is told at its tail to answer.
        roundParams.systemPrompt = [params.systemPrompt, format.instructions(for: specs)].compactMap { $0 }.joined(separator: "\n\n")
        var sent = messages + rounds.flatMap { round in
            [ChatMessage(role: .assistant, content: round.text),
             ChatMessage(role: .user, content: format.resultMessage(round.results.map { ($0.name, ToolRunScope.modelText(for: $0)) }))]
        }
        if !toolsOn {
            if let last = sent.indices.last, sent[last].role == .user {
                sent[last].content += "\n\n" + Self.answerNow
            } else {
                sent.append(ChatMessage(role: .user, content: Self.answerNow))
            }
        }
        return (sent, roundParams)
    }
}
