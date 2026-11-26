import Foundation

/// Reads the body of a streamable HTTP response: plain JSON or a server-sent-event stream.
enum MCPWire {
    static func messages(data: Data, contentType: String?) throws -> [JSONValue] {
        if contentType?.lowercased().contains("text/event-stream") == true {
            var parser = SSEParser()
            let payloads = parser.feed(data) + parser.finish()
            // Events with empty or non-JSON data (priming events) carry no message.
            return payloads.compactMap { JSONValue.parse($0) }
        }
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            throw MCPError.invalidResponse("The body is not JSON.")
        }
        if case .array(let batch) = value { return batch }
        return [value]
    }

    /// The `result` for request `id`, or the JSON-RPC error answering it.
    static func result(id: Int, in messages: [JSONValue]) throws -> JSONValue {
        for message in messages {
            guard let number = message["id"]?.number, Int(exactly: number) == id else { continue }
            if let error = message["error"] {
                throw MCPError.rpc(
                    code: error["code"]?.number.flatMap { Int(exactly: $0) } ?? 0,
                    message: error["message"]?.string ?? "Unknown error."
                )
            }
            if let result = message["result"] { return result }
        }
        throw MCPError.invalidResponse("No answer for request \(id).")
    }
}
