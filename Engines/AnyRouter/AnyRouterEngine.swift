import Foundation

/// Reads the signed-in user's key. The engine never stores or logs it.
protocol TokenStoring: Sendable {
    func token() -> String?
    func clear()
}

/// AnyRouter cloud models over the OpenAI-compatible API.
struct AnyRouterEngine: ResumableEngine, SubagentEngine {
    var source: ModelSource { .anyrouter }

    let tokens: any TokenStoring
    let session: URLSession
    let config: AnyRouterConfig
    let onUnauthorized: @Sendable () async -> Void
    /// Where attached photos are read from when a vision model gets them.
    let attachments: AttachmentStore

    init(
        tokens: any TokenStoring,
        config: AnyRouterConfig = .standard,
        session: URLSession = .shared,
        attachments: AttachmentStore = .shared,
        onUnauthorized: @escaping @Sendable () async -> Void = {}
    ) {
        self.attachments = attachments
        self.tokens = tokens
        self.config = config
        self.session = session
        self.onUnauthorized = onUnauthorized
    }

    func availableModels() async throws -> [ModelDescriptor] {
        let (models, usable) = try await fetchCatalog()
        return models.descriptors(usable: usable)
    }

    /// Decision models from the same catalog call. They are not chat models, so they are not in `availableModels()`.
    func decisionModels() async throws -> [ModelDescriptor] {
        let (models, usable) = try await fetchCatalog()
        return models.decisionDescriptors(usable: usable)
    }

    private func fetchCatalog() async throws -> (models: ModelsResponse, usable: Bool) {
        let key = tokens.token()
        var request = URLRequest(url: config.baseURL.appending(path: "models"))
        // The picker waits for this list; do not let a dead connection hold it for a minute.
        request.timeoutInterval = 15
        applyHeaders(&request, key: key)
        let (data, response) = try await session.data(for: request)
        let status = AnyRouterError.status(of: response)
        if status == 401, key != nil {
            tokens.clear()
            await onUnauthorized()
        }
        guard (200..<300).contains(status) else {
            throw AnyRouterError.http(status: status, message: AnyRouterError.message(from: data, status: status))
        }
        // Entries that do not read are skipped inside `ModelsResponse`; only a body that is not a catalog fails here.
        guard let decoded = try? JSONDecoder().decode(ModelsResponse.self, from: data) else { throw AnyRouterError.badResponse }
        return (decoded, key != nil && status != 401)
    }

    func stream(
        model: ModelDescriptor,
        messages: [ChatMessage],
        params: GenerationParams
    ) -> AsyncThrowingStream<ChatDelta, Error> {
        stream(model: model, messages: messages, params: params, tools: nil)
    }

    /// Most tool rounds one reply may take. After that the model is told to answer without tools.
    static let maxToolSteps = 8

    /// Streams a reply through the app's tool loop (`AgentLoop`): each round is one request. With a `ToolHost` the
    /// loop runs the calls the model asks for and sends their results back, until the model answers in plain text.
    func stream(
        model: ModelDescriptor,
        messages: [ChatMessage],
        params: GenerationParams,
        tools host: (any ToolHost)?
    ) -> AsyncThrowingStream<ChatDelta, Error> {
        stream(model: model, messages: messages, params: params, tools: host, resuming: nil)
    }

    /// The same loop, going on from a run that stopped for approval when `resuming` is set (agent design 1.3).
    func stream(
        model: ModelDescriptor, messages: [ChatMessage], params: GenerationParams, tools host: (any ToolHost)?, resuming: AgentResume?
    ) -> AsyncThrowingStream<ChatDelta, Error> {
        let step = AnyRouterStep(engine: self, model: model, messages: messages, params: params, specs: host?.specs ?? [])
        return AgentLoop.stream(step: step, host: host, maxToolRounds: Self.maxToolSteps, resume: resuming)
    }

    /// A subagent's rounds: the same model with the subagent's own messages, prompt and tools.
    func childStep(model: ModelDescriptor, messages: [ChatMessage], params: GenerationParams, specs: [ToolSpec]) -> any StepFunction {
        AnyRouterStep(engine: self, model: model, messages: messages, params: params, specs: specs)
    }

    /// One request: text and reasoning go out as they arrive; the proposed calls, usage, metadata and finish reason
    /// at the end.
    fileprivate func streamRound(_ request: URLRequest, emit: (StepEvent) -> Void) async throws {
        let (bytes, response) = try await session.bytes(for: request)
        let status = AnyRouterError.status(of: response)
        guard (200..<300).contains(status) else {
            var body = Data()
            try await bytes.forEachChunk { chunk in
                body.append(chunk)
                return body.count <= 16 * 1024
            }
            if status == 401 {
                tokens.clear()
                await onUnauthorized()
                throw AnyRouterError.signedOut
            }
            throw AnyRouterError.http(status: status, message: AnyRouterError.message(from: body, status: status))
        }

        var parser = SSEParser()
        var decoder = ChatChunkDecoder()
        var usage: Usage?
        var metadata: ResponseMetadata?
        func handle(_ payloads: [String]) throws {
            for payload in payloads {
                for delta in try decoder.decode(payload) {
                    switch delta {
                    case .text(let piece):
                        emit(.text(piece))
                    case .reasoning(let piece):
                        emit(.reasoning(piece))
                    case .usage(let next):
                        usage = next
                    case .metadata(let next):
                        metadata = next
                    case .done, .toolCall, .toolResult:
                        break
                    }
                }
            }
        }
        try await bytes.forEachChunk(endingAt: 0x0A) { chunk in
            try handle(parser.feed(chunk))
            return true
        }
        try handle(parser.finish())
        for call in decoder.toolCalls { emit(.proposed(call)) }
        if let usage { emit(.usage(usage)) }
        if let metadata { emit(.metadata(metadata)) }
        emit(.end(finishReason: decoder.finishReason))
    }

    /// A finished round as the API wants it back: the assistant's turn with its calls, then one `tool` message per result.
    static func wireMessages(_ round: AgentRound) -> [[String: Any]] {
        [assistantMessage(text: round.text, calls: round.calls)]
            + zip(round.calls, round.results).map { call, result in ["role": "tool", "tool_call_id": call.id, "content": result.text] }
    }

    /// The assistant turn that asked for tools, replayed to the model together with the results.
    static func assistantMessage(text: String, calls: [ToolCall]) -> [String: Any] {
        [
            "role": "assistant",
            "content": text.isEmpty ? NSNull() : text,
            "tool_calls": calls.map { call -> [String: Any] in
                [
                    "id": call.id,
                    "type": "function",
                    "function": ["name": call.name, "arguments": call.argumentsJSON],
                ]
            },
        ]
    }

    // MARK: Request building

    func makeChatRequest(
        key: String,
        model: ModelDescriptor,
        messages: [ChatMessage],
        params: GenerationParams,
        tools: [ToolSpec] = [],
        toolChoiceNone: Bool = false,
        extraMessages: [[String: Any]] = []
    ) throws -> URLRequest {
        var wire: [[String: Any]] = []
        if let system = params.systemPrompt, !system.isEmpty {
            wire.append(["role": "system", "content": system])
        }
        let sendsImages = model.supportsVision
        wire += messages.map { Self.wireMessage($0, sendsImages: sendsImages, store: attachments) }
        wire += extraMessages

        var body: [String: Any] = [
            "model": Self.wireModelID(model.id),
            "messages": wire,
            "stream": true,
            "stream_options": ["include_usage": true],
            "temperature": params.temperature,
            "top_p": params.topP,
        ]
        if let max = params.maxTokens { body["max_tokens"] = max }
        if !tools.isEmpty {
            body["tools"] = tools.map(Self.wireTool)
            body["tool_choice"] = toolChoiceNone ? "none" : "auto"
        }

        var request = URLRequest(url: config.baseURL.appending(path: "chat/completions"))
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        applyHeaders(&request, key: key)
        return request
    }

    /// One chat message. A vision model gets photos as OpenAI content parts (`image_url` with a data URL);
    /// every other model gets the message and its files as plain text.
    static func wireMessage(_ message: ChatMessage, sendsImages: Bool, store: AttachmentStore) -> [String: Any] {
        let text = AttachmentPrompt.text(for: message, sendsImages: sendsImages)
        let images = sendsImages && message.role == .user ? message.attachments.filter { $0.kind == .image } : []
        guard !images.isEmpty else { return ["role": message.role.rawValue, "content": text] }
        var parts: [[String: Any]] = []
        if !text.isEmpty { parts.append(["type": "text", "text": text]) }
        for image in images {
            guard let data = store.data(for: image) else {
                parts.append(["type": "text", "text": "[Image: \(image.filename). The file is missing.]"])
                continue
            }
            parts.append(["type": "image_url",
                          "image_url": ["url": "data:\(image.mimeType);base64,\(data.base64EncodedString())"]])
        }
        return ["role": message.role.rawValue, "content": parts]
    }

    /// OpenAI `tools` entry. The schema goes as the tool gave it, whole; one that is not a JSON object degrades to "no
    /// arguments".
    static func wireTool(_ spec: ToolSpec) -> [String: Any] {
        let schema = (try? JSONSerialization.jsonObject(with: Data(spec.schema.wireObject.jsonString().utf8))) as? [String: Any]
        return [
            "type": "function",
            "function": [
                "name": spec.name,
                "description": spec.description,
                "parameters": schema ?? ["type": "object", "properties": [String: Any]()],
            ] as [String: Any],
        ]
    }

    /// `anyrouter/<provider/model>` is our id; the API wants `<provider/model>`.
    static func wireModelID(_ id: String) -> String {
        id.hasPrefix("anyrouter/") ? String(id.dropFirst("anyrouter/".count)) : id
    }

    func applyHeaders(_ request: inout URLRequest, key: String?) {
        if let key { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        request.setValue(config.referer, forHTTPHeaderField: "HTTP-Referer")
        request.setValue(config.clientName, forHTTPHeaderField: "X-AnyRouter-Title")
        request.setValue(config.source, forHTTPHeaderField: "X-AnyRouter-Source")
        request.setValue(config.version, forHTTPHeaderField: "X-AnyRouter-Version")
        request.setValue(config.categories, forHTTPHeaderField: "X-AnyRouter-Categories")
    }
}

/// One AnyRouter request as a round of the app's tool loop (agent design 1.4). Earlier rounds go back as the assistant's
/// `tool_calls` and their `tool` messages. With tools off the request still lists the tools (the history mentions them)
/// but sets `tool_choice` to `none`.
struct AnyRouterStep: StepFunction {
    let engine: AnyRouterEngine
    let model: ModelDescriptor
    let messages: [ChatMessage]
    let params: GenerationParams
    let specs: [ToolSpec]

    /// Cloud results are sent whole; old ones are cleared only in large steps, and only when the window is known.
    var budget: RunBudgetLogic.Budget? {
        CompactionLogic.window(for: model).map { RunBudgetLogic.Budget(window: $0, onDevice: false) }
    }

    func tokens(_ rounds: [AgentRound], toolsOn: Bool) -> Int {
        let sent = [params.systemPrompt].compactMap { $0 } + messages.map(\.content)
            + rounds.flatMap { [$0.text] + $0.calls.map(\.argumentsJSON) + $0.results.map(\.text) }
        return sent.reduce(0) { $0 + TokenCountLogic.estimate($1) + PromptAssembler.perMessageTokens }
    }

    func step(_ rounds: [AgentRound], toolsOn: Bool) -> AsyncThrowingStream<StepEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let key = engine.tokens.token() else { throw AnyRouterError.signedOut }
                    let request = try engine.makeChatRequest(
                        key: key, model: model, messages: messages, params: params,
                        tools: specs, toolChoiceNone: !toolsOn, extraMessages: rounds.flatMap(AnyRouterEngine.wireMessages)
                    )
                    try await engine.streamRound(request) { _ = continuation.yield($0) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
