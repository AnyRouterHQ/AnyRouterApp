import Foundation

/// What one request used (agent v2 U1 and K1a). `input` counts every prompt token. `cacheRead` and `cacheWrite` are
/// the parts a provider cache served or stored. `decoded` is what a local engine actually ran through the model, input
/// less what a kept context saved (nil for an engine that does not say). `reasoning` is the share of `output` that was
/// reasoning.
struct Usage: Hashable, Sendable {
    var input: Int
    var output: Int
    var cacheRead: Int = 0
    var cacheWrite: Int = 0
    var decoded: Int? = nil
    var reasoning: Int = 0
    var costUSD: Decimal? = nil

    /// Two rounds of one reply, added up.
    static func + (lhs: Usage, rhs: Usage) -> Usage {
        Usage(
            input: lhs.input + rhs.input, output: lhs.output + rhs.output, cacheRead: lhs.cacheRead + rhs.cacheRead,
            cacheWrite: lhs.cacheWrite + rhs.cacheWrite, decoded: plus(lhs.decoded, rhs.decoded),
            reasoning: lhs.reasoning + rhs.reasoning, costUSD: plus(lhs.costUSD, rhs.costUSD))
    }

    private static func plus<T: AdditiveArithmetic>(_ a: T?, _ b: T?) -> T? {
        switch (a, b) {
        case let (x?, y?): x + y
        case let (x?, nil): x
        case let (nil, y?): y
        case (nil, nil): nil
        }
    }
}
