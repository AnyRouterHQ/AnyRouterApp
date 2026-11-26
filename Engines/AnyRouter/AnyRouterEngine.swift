import Foundation

/// Reads the signed-in user's key. The engine never stores or logs it.
protocol TokenStoring: Sendable {
    func token() -> String?
    func clear()
}

/// AnyRouter cloud models over the OpenAI-compatible API.
struct AnyRouterEngine: ChatEngine {
    var source: ModelSource { .anyrouter }

    private let tokens: any TokenStoring
    private let session: URLSession
    private let config: AnyRouterConfig
    private let onUnauthorized: @Sendable () async -> Void

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
        return decoded.descriptors(usable: key != nil && status != 401)
    }

    func stream(
        model: ModelDescriptor,
        messages: [ChatMessage],
        params: GenerationParams
    ) -> AsyncThrowingStream<ChatDelta, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let key = tokens.token() else { throw AnyRouterError.signedOut }
                    let request = try makeChatRequest(key: key, model: model, messages: messages, params: params)
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
                    var pending = Data()
                    for try await byte in bytes {
                        pending.append(byte)
                        guard byte == 0x0A else { continue }
                        for payload in parser.feed(pending) {
                            for delta in try decoder.decode(payload) { continuation.yield(delta) }
                        }
                        pending.removeAll(keepingCapacity: true)
                    }
                    for payload in parser.feed(pending) + parser.finish() {
                        for delta in try decoder.decode(payload) { continuation.yield(delta) }
                    }
                    if !decoder.isDone { continuation.yield(.done(finishReason: decoder.finishReason)) }
                    continuation.finish()
                } catch {
                    // A cancelled consumer is not an error; URLSession reports it as URLError.cancelled.
                    if Task.isCancelled {
                        continuation.finish()
                    } else {
                        continuation.finish(throwing: error)
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: Request building

    func makeChatRequest(
        key: String,
        model: ModelDescriptor,
        messages: [ChatMessage],
        params: GenerationParams
    ) throws -> URLRequest {
        var wire: [[String: String]] = []
        if let system = params.systemPrompt, !system.isEmpty {
            wire.append(["role": "system", "content": system])
        }
        wire += messages.map { ["role": $0.role.rawValue, "content": $0.content] }

        var body: [String: Any] = [
            "model": Self.wireModelID(model.id),
            "messages": wire,
            "stream": true,
            "stream_options": ["include_usage": true],
            "temperature": params.temperature,
            "top_p": params.topP,
        ]
        if let max = params.maxTokens { body["max_tokens"] = max }

        var request = URLRequest(url: config.baseURL.appending(path: "chat/completions"))
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        applyHeaders(&request, key: key)
        return request
    }

    /// `anyrouter/<provider/model>` is our id; the API wants `<provider/model>`.
    static func wireModelID(_ id: String) -> String {
        id.hasPrefix("anyrouter/") ? String(id.dropFirst("anyrouter/".count)) : id
    }

    private func applyHeaders(_ request: inout URLRequest, key: String?) {
        if let key { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        request.setValue(config.referer, forHTTPHeaderField: "HTTP-Referer")
        request.setValue(config.clientName, forHTTPHeaderField: "X-AnyRouter-Title")
        request.setValue(config.source, forHTTPHeaderField: "X-AnyRouter-Source")
        request.setValue(config.version, forHTTPHeaderField: "X-AnyRouter-Version")
        request.setValue(config.categories, forHTTPHeaderField: "X-AnyRouter-Categories")
    }
}
