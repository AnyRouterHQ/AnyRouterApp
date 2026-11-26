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
                if let delta = choice["delta"] as? [String: Any],
                    let text = delta["content"] as? String, !text.isEmpty {
                    deltas.append(.text(text))
                }
                if let reason = choice["finish_reason"] as? String { finishReason = reason }
            }
        }
        if let usage = json["usage"] as? [String: Any],
            let prompt = (usage["prompt_tokens"] as? NSNumber)?.intValue,
            let completion = (usage["completion_tokens"] as? NSNumber)?.intValue {
            deltas.append(.usage(prompt: prompt, completion: completion))
        }
        return deltas
    }
}
