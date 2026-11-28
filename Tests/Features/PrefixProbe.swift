import Foundation
@testable import AnyRouter

/// The prompt-cache probe (agent v2 U5, agent design E2). Every cache the app can use depends on a byte-stable prefix: a
/// local model's KV cache, Apple's session and the provider caches behind AnyRouter each reuse a request only as far as
/// it repeats the request before it, byte for byte. The probe holds each recorded request to the one before it.
enum PrefixProbe {
    /// A request in the order a model reads it.
    enum Part: String, Hashable, Sendable {
        case tools, system, messages
    }

    /// A break the run made on purpose and named in its record. The request after it may start over.
    enum PlannedBreak: String, CaseIterable, Sendable {
        /// Old tool results cleared to fit the window (U20).
        case clearedResults
        /// The chat folded into a summary (U18).
        case compaction
        /// Old photos dropped at a compaction (U17).
        case droppedPhotos
    }

    struct Request: Equatable, Sendable {
        var tools = Data()
        var system = Data()
        var messages = Data()
        var planned: PlannedBreak?
    }

    struct Break: Equatable, Sendable, CustomStringConvertible {
        /// The request that did not keep the one before it.
        var request: Int
        var part: Part
        var offset: Int

        var description: String { "request \(request) changed its \(part.rawValue) at byte \(offset)" }
    }

    /// The first byte where `next` stops repeating `previous`, or nil when `next` starts with all of `previous`.
    static func firstDivergence(previous: Data, next: Data) -> Int? {
        let shared = zip(previous, next).prefix(while: { $0 == $1 }).count
        return shared == previous.count ? nil : shared
    }

    /// Each request extends the one before it up to the start of its newest exchange: the same tools, the same system
    /// message, and every earlier message unchanged. A request whose run planned a break is not held to it.
    static func breaks(_ requests: [Request]) -> [Break] {
        var found: [Break] = []
        for index in requests.indices.dropFirst() where requests[index].planned == nil {
            let previous = requests[index - 1], next = requests[index]
            let offsets: [(Part, Int?)] = [
                (.tools, changed(previous.tools, next.tools)),
                (.system, changed(previous.system, next.system)),
                (.messages, firstDivergence(previous: previous.messages, next: next.messages)),
            ]
            for case let (part, offset?) in offsets {
                found.append(Break(request: index, part: part, offset: offset))
            }
        }
        return found
    }

    /// Where `next` differs from `previous`, or nil when they are the same bytes. Growing counts as a change here: a tool
    /// or a line added to the system message moves every byte after it.
    private static func changed(_ previous: Data, _ next: Data) -> Int? {
        guard previous != next else { return nil }
        return firstDivergence(previous: previous, next: next) ?? previous.count
    }
}

extension PrefixProbe.Request {
    /// An AnyRouter request body as a provider reads it: the tools, then the system message, then each message.
    /// Each JSON object is written again with sorted keys. The app writes `[String: Any]` without them
    /// (AnyRouterEngine.makeChatRequest and wireTool), and Swift seeds each dictionary's hash from its storage address,
    /// so two requests in one process can order the same keys differently. The probe therefore cannot see key order;
    /// U10's golden test does.
    init(cloudBody body: Data) throws {
        guard let object = try JSONSerialization.jsonObject(with: body) as? [String: Any],
              let messages = object["messages"] as? [[String: Any]]
        else { throw TestFailure(message: "Not a chat request.") }
        let isSystem = { (message: [String: Any]) in message["role"] as? String == "system" }
        self.init(
            tools: try Self.lines(object["tools"] as? [[String: Any]] ?? []),
            system: try Self.lines(messages.filter(isSystem)),
            messages: try Self.lines(messages.filter { !isSystem($0) }))
    }

    /// What a local engine is given: its system prompt and the messages' roles and text. The chat template that llama.cpp
    /// or MLX applies to them, and the photos a vision model decodes, are past this seam and not compared.
    init(localSystem system: String?, messages: [ChatMessage]) throws {
        self.init(
            system: Data((system ?? "").utf8),
            messages: try Self.lines(messages.map { message -> [String: Any] in
                ["role": message.role.rawValue, "content": message.content]
            }))
    }

    private static func lines(_ objects: [[String: Any]]) throws -> Data {
        try objects.reduce(into: Data()) { data, object in
            data += try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            data.append(0x0A)
        }
    }
}
