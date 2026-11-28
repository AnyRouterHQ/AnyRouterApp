import Foundation

/// What is known about one reply: who served it, what it cost, and how fast it came.
/// AnyRouter sends most of it in the last stream chunk; the chat measures the timings.
/// Local and Apple models report cost 0 and provider "On device".
struct ResponseMetadata: Hashable, Codable, Sendable {
    var requestID: String?
    /// The model that really answered. For `anyrouter/auto` this is the routed model.
    var servedModelID: String?
    var servedModelName: String?
    var provider: String?
    var costUSD: Decimal?
    var promptTokens: Int?
    var completionTokens: Int?
    var cachedTokens: Int?
    var upstreamLatencyMs: Int?
    /// Send to first text, measured by the chat.
    var ttftMs: Int?
    /// Send to the end of the reply, measured by the chat.
    var totalMs: Int?
    /// Time the reply waited on its tool calls (a subagent's whole run, a page fetch), measured by the chat. Not the
    /// model's generation time, so the speed leaves it out.
    var toolMs: Int?
    /// What a subagent of this reply spent, apart from the reply's own tokens, so the speed counts only the reply's.
    var subagentPromptTokens: Int?
    var subagentCompletionTokens: Int?
    /// Prompt tokens a local engine actually ran through the model (agent v2 U1). Equal to `promptTokens` while every
    /// request prefills its whole prompt; a kept context makes it smaller, and decoded over prompt is the measure.
    var decodedTokens: Int?

    /// The reply's own generated tokens per second, after the first token arrived, without the time spent in tools.
    var tokensPerSecond: Double? {
        guard let completionTokens, completionTokens > 0, let totalMs, let ttftMs else { return nil }
        let generating = totalMs - ttftMs - (toolMs ?? 0)
        guard generating > 0 else { return nil }
        let seconds = Double(generating) / 1000
        guard seconds >= 0.05 else { return nil }
        return Double(completionTokens) / seconds
    }

    /// Adds the numbers of two rounds of one reply (a tool call needs a second request).
    /// Names and ids come from the later round.
    static func combining(_ first: ResponseMetadata?, _ second: ResponseMetadata?) -> ResponseMetadata? {
        guard var result = first else { return second }
        guard let next = second else { return result }
        func add<T: AdditiveArithmetic>(_ a: T?, _ b: T?) -> T? {
            switch (a, b) {
            case let (x?, y?): return x + y
            case let (x?, nil): return x
            case let (nil, y?): return y
            case (nil, nil): return nil
            }
        }
        result.costUSD = add(result.costUSD, next.costUSD)
        result.promptTokens = add(result.promptTokens, next.promptTokens)
        result.completionTokens = add(result.completionTokens, next.completionTokens)
        result.cachedTokens = add(result.cachedTokens, next.cachedTokens)
        result.decodedTokens = add(result.decodedTokens, next.decodedTokens)
        result.upstreamLatencyMs = add(result.upstreamLatencyMs, next.upstreamLatencyMs)
        result.requestID = next.requestID ?? result.requestID
        result.servedModelID = next.servedModelID ?? result.servedModelID
        result.servedModelName = next.servedModelName ?? result.servedModelName
        result.provider = next.provider ?? result.provider
        return result
    }
}
