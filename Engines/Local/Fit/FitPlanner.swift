import Foundation

/// What a model costs in memory, enough to estimate its footprint at any context size.
struct ModelMemoryProfile: Equatable, Sendable {
    var fileBytes: Int64
    /// KV-cache bytes per token over the layers that attend to the whole context (f16 cache).
    var fullKVBytesPerToken: Int64
    /// KV-cache bytes per token over sliding-window layers. These never hold more than `windowTokens` tokens.
    var windowKVBytesPerToken: Int64 = 0
    var windowTokens: Int = 0
    /// Context length the model was trained for. Zero when unknown.
    var trainedContext: Int
    /// Share of the weights that one token touches in a mixture-of-experts model. Nil for dense models.
    var activeFraction: Double?
    /// True when the KV numbers are a guess from the file size, not read from the model's metadata.
    var isEstimated: Bool = false
    /// Weights that stay out of RAM with mmap: tables only read row by row (token embeddings, the per-layer embeddings
    /// of Gemma 4). llama.cpp keeps them in CPU buffers over the mapped file, so only the rows a prompt touches load.
    var lazyBytes: Int64 = 0

    /// File bytes that must be in RAM while the model runs.
    var residentBytes: Int64 { max(0, fileBytes - max(0, lazyBytes)) }

    func kvBytes(context: Int) -> Int64 {
        // The numbers can come from a catalog file or a GGUF header the user added: bound them so the products cannot overflow.
        let tokens = Int64(min(max(context, 0), 1 << 22))
        let full = min(max(fullKVBytesPerToken, 0), 1 << 36) * tokens
        let window = min(max(windowKVBytesPerToken, 0), 1 << 36) * min(tokens, Int64(max(windowTokens, 0)))
        return full + window
    }

    /// Weights one token reads. With mmap, a mixture-of-experts model only keeps these (plus churn) in RAM.
    var activeBytes: Int64 {
        activeFraction.map { Int64(Double(residentBytes) * $0) } ?? residentBytes
    }

    /// Guess for a model whose metadata is not known (a repo the user added, before the header is read).
    /// About 40 KB per token plus 60 KB per GB of weights: a bit high for small models, close for 4B-class ones.
    static func estimated(fileBytes: Int64, trainedContext: Int) -> ModelMemoryProfile {
        let gigabytes = Double(fileBytes) / 1_000_000_000
        return ModelMemoryProfile(
            fileBytes: fileBytes, fullKVBytesPerToken: Int64(40_000 + 60_000 * gigabytes),
            trainedContext: trainedContext, activeFraction: nil, isEstimated: true)
    }

    /// Dense weights are never all touched in a mixture-of-experts model: attention, embeddings and shared layers
    /// (about 6% of the file) plus the experts a token is routed to.
    static func activeFraction(expertCount: Int, expertsUsed: Int) -> Double? {
        guard expertCount > 1, expertsUsed > 0, expertsUsed <= expertCount else { return nil }
        let value = 0.06 + 0.94 * Double(expertsUsed) / Double(expertCount)
        return (value * 1000).rounded() / 1000
    }
}

/// What the app may use for a model on this device right now.
struct DeviceMemory: Equatable, Sendable {
    /// Bytes a model (weights, KV cache and runtime buffers) may take: the process limit minus the app's own use.
    var budgetBytes: Int64
    /// Installed RAM, for display.
    var physicalBytes: Int64

    /// The app itself (UI, database, markdown, networking) before any model.
    static let appBaselineBytes: Int64 = 300_000_000
}

struct FitEstimate: Equatable, Sendable {
    enum Verdict: Equatable, Sendable {
        case runsWell
        /// It loads, but only with a smaller context and shorter replies than the model supports.
        case tight(maxContext: Int, maxReply: Int)
        case wontFit
    }

    var fileBytes: Int64
    /// KV cache at `context`.
    var kvBytes: Int64
    var overheadBytes: Int64
    /// Weights, KV cache and overhead: what the model needs to run entirely in RAM.
    var totalBytes: Int64
    var deviceBudgetBytes: Int64
    /// The context this estimate is for: the largest that fits, up to `FitPlanner.maxContext`.
    var context: Int
    var verdict: Verdict
    /// Only the experts in use stay in RAM; the rest of the file is read from storage on demand (slower).
    var streamsFromStorage: Bool
    var isEstimated: Bool
}

/// The fit math, with no device calls: give it a profile and a budget.
enum FitPlanner {
    /// Runtime buffers, compute graphs and the Metal heap, on top of weights and KV cache.
    static let overheadBytes: Int64 = 1_000_000_000
    /// Context sizes are multiples of this.
    static let contextStep = 256
    /// Below this a chat is not useful.
    static let minContext = 512
    /// A model only "runs well" when this much context fits with headroom (or the model's own limit, if smaller).
    static let preferredContext = 4096
    /// Upper bound on what the app asks for, to keep prefill and KV memory in check.
    static let maxContext = 8192
    /// A model "runs well" only when it leaves this share of the budget unused.
    static let headroom = 0.85

    static func estimate(_ profile: ModelMemoryProfile, memory: DeviceMemory) -> FitEstimate {
        let budget = memory.budgetBytes
        let cap = contextCap(profile)
        let comfortable = Int64(Double(budget) * headroom)
        let preferred = min(cap, preferredContext)
        func make(_ verdict: FitEstimate.Verdict, context: Int, streams: Bool = false) -> FitEstimate {
            let kv = profile.kvBytes(context: context)
            return FitEstimate(
                fileBytes: profile.fileBytes, kvBytes: kv, overheadBytes: overheadBytes,
                totalBytes: profile.residentBytes + kv + overheadBytes, deviceBudgetBytes: budget, context: context,
                verdict: verdict, streamsFromStorage: streams, isEstimated: profile.isEstimated)
        }

        if let context = largestContext(profile, resident: profile.residentBytes, limit: comfortable, cap: cap), context >= preferred {
            return make(.runsWell, context: context)
        }
        let inMemory = largestContext(profile, resident: profile.residentBytes, limit: budget, cap: cap)
        // A mixture-of-experts model can also run from mmap: only the experts in use are resident, the rest is paged in
        // from storage (slower). It wins when the whole file would leave less than the preferred context.
        let streamed = profile.activeFraction == nil
            ? nil : largestContext(profile, resident: profile.activeBytes, limit: budget, cap: cap)
        if let streamed, streamed > (inMemory ?? 0), (inMemory ?? 0) < preferred {
            return make(.tight(maxContext: streamed, maxReply: maxReply(forContext: streamed)), context: streamed, streams: true)
        }
        if let inMemory {
            return make(.tight(maxContext: inMemory, maxReply: maxReply(forContext: inMemory)), context: inMemory)
        }
        return make(.wontFit, context: minContext)
    }

    /// The context to load with: the largest that fits the budget, or nil when even the minimum does not.
    /// Models that run well get headroom; tight ones use the whole budget.
    static func pickContext(_ profile: ModelMemoryProfile, memory: DeviceMemory) -> Int? {
        let estimate = estimate(profile, memory: memory)
        return estimate.verdict == .wontFit ? nil : estimate.context
    }

    /// Replies are short on a small context so the prompt keeps room.
    static func maxReply(forContext context: Int) -> Int {
        max(64, min(512, context / 8))
    }

    private static func contextCap(_ profile: ModelMemoryProfile) -> Int {
        let trained = profile.trainedContext > 0 ? profile.trainedContext : maxContext
        return max(minContext, min(trained, maxContext)) / contextStep * contextStep
    }

    /// Largest multiple of `contextStep` in `minContext...cap` whose weights, KV cache and overhead fit `limit`.
    private static func largestContext(_ profile: ModelMemoryProfile, resident: Int64, limit: Int64, cap: Int) -> Int? {
        func fits(_ context: Int) -> Bool { resident + profile.kvBytes(context: context) + overheadBytes <= limit }
        guard fits(minContext) else { return nil }
        var low = minContext / contextStep
        var high = cap / contextStep
        while low < high {
            let middle = (low + high + 1) / 2
            if fits(middle * contextStep) { low = middle } else { high = middle - 1 }
        }
        return low * contextStep
    }
}
