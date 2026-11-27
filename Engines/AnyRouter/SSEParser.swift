import Foundation

/// Incremental server-sent-events parser. Feed raw bytes as they arrive (any split);
/// it returns the `data` payload of each completed event.
struct SSEParser {
    private var buffer = Data()
    private var dataLines: [String] = []

    mutating func feed(_ chunk: Data) -> [String] {
        buffer.append(chunk)
        var events: [String] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            var line = buffer[buffer.startIndex..<newline]
            if line.last == 0x0D { line = line.dropLast() }
            buffer = Data(buffer[buffer.index(after: newline)...])
            if let event = consume(String(decoding: line, as: UTF8.self)) { events.append(event) }
        }
        return events
    }

    /// Call when the connection ends: flushes an event the server did not terminate with a blank line.
    mutating func finish() -> [String] {
        var events: [String] = []
        if !buffer.isEmpty {
            var line = buffer
            if line.last == 0x0D { line = line.dropLast() }
            buffer = Data()
            if let event = consume(String(decoding: line, as: UTF8.self)) { events.append(event) }
        }
        if !dataLines.isEmpty {
            events.append(dataLines.joined(separator: "\n"))
            dataLines = []
        }
        return events
    }

    private mutating func consume(_ line: String) -> String? {
        if line.isEmpty {
            guard !dataLines.isEmpty else { return nil }
            defer { dataLines = [] }
            return dataLines.joined(separator: "\n")
        }
        if line.hasPrefix(":") { return nil }  // comment / keep-alive
        if line == "data" {
            dataLines.append("")
        } else if line.hasPrefix("data:") {
            var value = line.dropFirst(5)
            if value.first == " " { value = value.dropFirst() }
            dataLines.append(String(value))
        }
        return nil
    }
}

/// Maps OpenAI-style streaming payloads to `ChatDelta`s.
struct ChatChunkDecoder {
    private(set) var finishReason: String?
    private(set) var isDone = false
    /// From the `anyrouter_metadata` of the last chunk, when the server sent it.
    private(set) var metadata: ResponseMetadata?
    private var usageSeen = false

    /// Tool calls arrive in fragments: the id and name once, the arguments in pieces, keyed by `index`.
    private struct ToolFragment {
        var id = ""
        var name = ""
        var arguments = ""
    }
    private var fragments: [Int: ToolFragment] = [:]

    /// Complete calls seen so far, in the order the model listed them. A missing id is replaced,
    /// empty arguments become `{}`, and a fragment that never got a name is dropped.
    var toolCalls: [ToolCall] {
        fragments.sorted { $0.key < $1.key }.compactMap { _, fragment in
            guard !fragment.name.isEmpty else { return nil }
            let arguments = fragment.arguments.trimmingCharacters(in: .whitespacesAndNewlines)
            return ToolCall(
                id: fragment.id.isEmpty ? "call_" + UUID().uuidString.prefix(8).lowercased() : fragment.id,
                name: fragment.name,
                argumentsJSON: arguments.isEmpty ? "{}" : fragment.arguments
            )
        }
    }

    mutating func decode(_ payload: String) throws -> [ChatDelta] {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "[DONE]" {
            isDone = true
            return [.done(finishReason: finishReason)]
        }
        guard let data = trimmed.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [] }

        if let error = json["error"] {
            if let object = error as? [String: Any], let text = object["message"] as? String {
                throw AnyRouterError.stream(text)
            }
            throw AnyRouterError.stream((error as? String) ?? "The model stopped with an error.")
        }

        var deltas: [ChatDelta] = []
        if let choices = json["choices"] as? [[String: Any]] {
            for choice in choices {
                if let delta = choice["delta"] as? [String: Any], let thought = Self.reasoning(in: delta) {
                    deltas.append(.reasoning(thought))
                }
                if let delta = choice["delta"] as? [String: Any],
                    let text = delta["content"] as? String, !text.isEmpty {
                    deltas.append(.text(text))
                }
                if let delta = choice["delta"] as? [String: Any], let calls = delta["tool_calls"] as? [[String: Any]] {
                    for call in calls { absorb(call) }
                }
                if let reason = choice["finish_reason"] as? String { finishReason = reason }
            }
        }
        if let usage = json["usage"] as? [String: Any],
            let prompt = (usage["prompt_tokens"] as? NSNumber)?.intValue,
            let completion = (usage["completion_tokens"] as? NSNumber)?.intValue {
            deltas.append(.usage(prompt: prompt, completion: completion))
            usageSeen = true
        }
        if let raw = json["anyrouter_metadata"] as? [String: Any], let parsed = Self.metadata(from: raw) {
            metadata = parsed
            deltas.append(.metadata(parsed))
            // Servers that only send the metadata still give token counts.
            if !usageSeen, let prompt = parsed.promptTokens, let completion = parsed.completionTokens {
                deltas.append(.usage(prompt: prompt, completion: completion))
                usageSeen = true
            }
        }
        return deltas
    }

    /// The reasoning in a stream delta. Servers name it `reasoning_content` or `reasoning`.
    static func reasoning(in delta: [String: Any]) -> String? {
        for key in ["reasoning_content", "reasoning"] {
            if let text = delta[key] as? String, !text.isEmpty { return text }
        }
        return nil
    }

    /// `anyrouter_metadata`: requestId, model, upstream {provider, backend, latencyMs}, usage, cost {amount, currency}.
    static func metadata(from raw: [String: Any]) -> ResponseMetadata? {
        func int(_ value: Any?) -> Int? {
            guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
            return number.intValue
        }
        let upstream = raw["upstream"] as? [String: Any]
        let usage = raw["usage"] as? [String: Any]
        let cost = raw["cost"] as? [String: Any]
        var costUSD: Decimal?
        if let amount = cost?["amount"] {
            let currency = (cost?["currency"] as? String)?.uppercased()
            if currency == nil || currency == "USD" {
                if let number = amount as? NSNumber { costUSD = Decimal(string: number.stringValue) }
                else if let text = amount as? String { costUSD = Decimal(string: text) }
            }
        }
        let metadata = ResponseMetadata(
            requestID: raw["requestId"] as? String,
            servedModelID: raw["model"] as? String,
            servedModelName: nil,
            provider: (upstream?["provider"] as? String) ?? (upstream?["backend"] as? String),
            costUSD: costUSD,
            promptTokens: int(usage?["inputTokens"]),
            completionTokens: int(usage?["outputTokens"]),
            cachedTokens: int(usage?["cachedTokens"]),
            upstreamLatencyMs: int(upstream?["latencyMs"]))
        return metadata == ResponseMetadata() ? nil : metadata
    }

    private mutating func absorb(_ call: [String: Any]) {
        let id = call["id"] as? String ?? ""
        var index = (call["index"] as? NSNumber)?.intValue ?? fragments.keys.max() ?? 0
        // Some providers leave `index` out; a new id then means a new call.
        if call["index"] == nil, !id.isEmpty, let existing = fragments[index], !existing.id.isEmpty, existing.id != id {
            index += 1
        }
        var fragment = fragments[index] ?? ToolFragment()
        if !id.isEmpty { fragment.id = id }
        if let function = call["function"] as? [String: Any] {
            // Some providers repeat the name in every fragment; keep the first.
            if let name = function["name"] as? String, !name.isEmpty, fragment.name.isEmpty { fragment.name = name }
            if let piece = function["arguments"] as? String { fragment.arguments += piece }
        }
        fragments[index] = fragment
    }
}
