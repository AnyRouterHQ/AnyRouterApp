import Foundation

/// Reads the signed-in user's key. The engine never stores or logs it.
protocol TokenStoring: Sendable {
    func token() -> String?
    func clear()
}

/// AnyRouter cloud models over the OpenAI-compatible API.
struct AnyRouterEngine: ChatEngine {
    var source: ModelSource { .anyrouter }

    let tokens: any TokenStoring
    let session: URLSession
    let config: AnyRouterConfig
    let onUnauthorized: @Sendable () async -> Void

    init(
        tokens: any TokenStoring,
        config: AnyRouterConfig = .standard,
        session: URLSession = .shared,
        onUnauthorized: @escaping @Sendable () async -> Void = {}
    ) {
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
    func decisionModels() async throws -> [DecisionModel] {
        try await fetchCatalog().models.decisionModels()
    }

    private func fetchCatalog() async throws -> (models: ModelsResponse, usable: Bool) {
        let key = tokens.token()
        var request = URLRequest(url: config.baseURL.appending(path: "models"))
        // The picker waits for this list; do not let a dead connection hold it for a minute.
        request.timeoutInterval = 15
        applyHeaders(&request, key: key)
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401, key != nil {
            tokens.clear()
            await onUnauthorized()
        }
        guard (200..<300).contains(status) else {
            throw AnyRouterError.http(status: status, message: AnyRouterError.message(from: data, status: status))
        }
        let decoded = try JSONDecoder().decode(ModelsResponse.self, from: data)
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

    /// Streams a reply. With a `ToolHost` the model may call its tools: each round streams text, then the
    /// engine runs the requested calls and sends their results back, until the model answers in plain text.
    func stream(
        model: ModelDescriptor,
        messages: [ChatMessage],
        params: GenerationParams,
        tools host: (any ToolHost)?
    ) -> AsyncThrowingStream<ChatDelta, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let specs = host?.specs ?? []
                    var transcript: [[String: Any]] = []
                    var usage: (prompt: Int, completion: Int)?
                    var finishReason: String?
                    var toolRounds = 0
                    while true {
                        try Task.checkCancellation()
                        guard let key = tokens.token() else { throw AnyRouterError.signedOut }
                        let forceAnswer = toolRounds >= Self.maxToolSteps
                        let request = try makeChatRequest(
                            key: key, model: model, messages: messages, params: params,
                            tools: specs, toolChoiceNone: forceAnswer, extraMessages: transcript
                        )
                        let round = try await streamRound(request) { _ = continuation.yield($0) }
                        if let used = round.usage {
                            usage = (prompt: (usage?.prompt ?? 0) + used.prompt, completion: (usage?.completion ?? 0) + used.completion)
                        }
                        finishReason = round.finishReason
                        guard let host, !round.toolCalls.isEmpty, !forceAnswer else { break }

                        transcript.append(Self.assistantMessage(text: round.text, calls: round.toolCalls))
                        for call in round.toolCalls {
                            try Task.checkCancellation()
                            continuation.yield(.toolCall(call))
                            let result = await host.execute(call)
                            try Task.checkCancellation()
                            continuation.yield(.toolResult(result))
                            transcript.append(["role": "tool", "tool_call_id": call.id, "content": result.text])
                        }
                        toolRounds += 1
                    }
                    if let usage { continuation.yield(.usage(prompt: usage.prompt, completion: usage.completion)) }
                    continuation.yield(.done(finishReason: finishReason))
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

    /// One request/response of the loop. Text goes out as it arrives; tool calls are collected.
    private struct Round {
        var text = ""
        var toolCalls: [ToolCall] = []
        var finishReason: String?
        var usage: (prompt: Int, completion: Int)?
    }

    private func streamRound(_ request: URLRequest, emit: (ChatDelta) -> Void) async throws -> Round {
        let (bytes, response) = try await session.bytes(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            var body = Data()
            for try await byte in bytes {
                body.append(byte)
                if body.count > 16 * 1024 { break }
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
        var round = Round()
        func handle(_ payloads: [String]) throws {
            for payload in payloads {
                for delta in try decoder.decode(payload) {
                    switch delta {
                    case .text(let piece):
                        round.text += piece
                        emit(delta)
                    case .usage(let prompt, let completion):
                        round.usage = (prompt, completion)
                    case .done, .toolCall, .toolResult:
                        break
                    }
                }
            }
        }
        var pending = Data()
        for try await byte in bytes {
            pending.append(byte)
            guard byte == 0x0A else { continue }
            try handle(parser.feed(pending))
            pending.removeAll(keepingCapacity: true)
        }
        try handle(parser.feed(pending) + parser.finish())
        round.toolCalls = decoder.toolCalls
        round.finishReason = decoder.finishReason
        return round
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
        wire += messages.map { message -> [String: Any] in ["role": message.role.rawValue, "content": message.content] }
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

    /// OpenAI `tools` entry. A schema that is not a JSON object degrades to "no arguments".
    static func wireTool(_ spec: ToolSpec) -> [String: Any] {
        let schema = (try? JSONSerialization.jsonObject(with: Data(spec.inputSchemaJSON.utf8))) as? [String: Any]
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
