import Foundation
import Testing
@testable import AnyRouter

private final class LockedList: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String] = []
    func append(_ item: String) { lock.withLock { stored.append(item) } }
    var items: [String] { lock.withLock { stored } }
}

private actor SizeLog {
    private(set) var sizes: [Int] = []
    var count: Int { sizes.count }
    func add(_ size: Int) { sizes.append(size) }
}

/// Builds a GGUF header (version 3, no tensors) from key/value pairs.
private struct HeaderBuilder {
    private(set) var data = Data()
    private var pairs: [(String, Data)] = []
    private var tensors: [(String, UInt64)] = []

    private static func le<T: FixedWidthInteger>(_ value: T) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }

    private static func string(_ text: String) -> Data {
        le(UInt64(text.utf8.count)) + Data(text.utf8)
    }

    mutating func string(_ key: String, _ value: String) {
        pairs.append((key, Self.le(UInt32(8)) + Self.string(value)))
    }

    mutating func u32(_ key: String, _ value: Int) {
        pairs.append((key, Self.le(UInt32(4)) + Self.le(UInt32(value))))
    }

    mutating func u32Array(_ key: String, _ values: [Int]) {
        var body = Self.le(UInt32(9)) + Self.le(UInt32(4)) + Self.le(UInt64(values.count))
        for value in values { body += Self.le(UInt32(value)) }
        pairs.append((key, body))
    }

    mutating func boolArray(_ key: String, _ values: [Bool]) {
        var body = Self.le(UInt32(9)) + Self.le(UInt32(7)) + Self.le(UInt64(values.count))
        for value in values { body.append(value ? 1 : 0) }
        pairs.append((key, body))
    }

    mutating func int8(_ key: String, _ value: Int8) {
        pairs.append((key, Self.le(UInt32(1)) + Data([UInt8(bitPattern: value)])))
    }

    /// An array header that promises far more elements than the file holds.
    mutating func array(_ key: String, element: UInt32, claiming count: UInt64) {
        pairs.append((key, Self.le(UInt32(9)) + Self.le(element) + Self.le(count)))
    }

    mutating func stringArray(_ key: String, count: Int) {
        var body = Self.le(UInt32(9)) + Self.le(UInt32(8)) + Self.le(UInt64(count))
        for index in 0..<count { body += Self.string("tok\(index)") }
        pairs.append((key, body))
    }

    /// A tensor-list entry: only the name and the data offset matter to the reader.
    mutating func tensor(_ name: String, offset: UInt64) {
        tensors.append((name, offset))
    }

    func build() -> Data {
        var out = Data("GGUF".utf8) + Self.le(UInt32(3)) + Self.le(UInt64(tensors.count)) + Self.le(UInt64(pairs.count))
        for (key, value) in pairs { out += Self.string(key) + value }
        for (name, offset) in tensors {
            out += Self.string(name) + Self.le(UInt32(2)) + Self.le(UInt64(64)) + Self.le(UInt64(64)) + Self.le(UInt32(2)) + Self.le(offset)
        }
        return out
    }
}

struct GGUFHeaderTests {
    @Test func aDenseModelCountsKVOnEveryLayer() throws {
        // Qwen3 4B: 36 layers, 8 KV heads, 128-dim K and V.
        var b = HeaderBuilder()
        b.string("general.architecture", "qwen3")
        b.u32("qwen3.block_count", 36)
        b.u32("qwen3.context_length", 40960)
        b.u32("qwen3.embedding_length", 2560)
        b.u32("qwen3.attention.head_count", 32)
        b.u32("qwen3.attention.head_count_kv", 8)
        b.u32("qwen3.attention.key_length", 128)
        b.u32("qwen3.attention.value_length", 128)
        let info = try GGUFHeader.parse(b.build())
        #expect(info.architecture == "qwen3" && info.blockCount == 36 && info.trainedContext == 40960)
        #expect(info.memory == CatalogMemory(fullKVBytesPerToken: 147_456))
    }

    @Test func headSizeFallsBackToEmbeddingOverHeads() throws {
        // Llama 3.2 1B: no explicit key length. 16 layers, 8 KV heads, 2048 / 32 = 64.
        var b = HeaderBuilder()
        b.string("general.architecture", "llama")
        b.u32("llama.block_count", 16)
        b.u32("llama.context_length", 131072)
        b.u32("llama.embedding_length", 2048)
        b.u32("llama.attention.head_count", 32)
        b.u32("llama.attention.head_count_kv", 8)
        let info = try GGUFHeader.parse(b.build())
        #expect(info.memory?.fullKVBytesPerToken == Int64(16 * 8 * (64 + 64) * 2))
    }

    @Test func gemma3WithoutAPatternKeyUsesFiveWindowLayersPerFullLayer() throws {
        // Gemma 3 1B: 26 layers, 1 KV head, 256-dim, 512-token window: 4 full layers and 22 window layers.
        var b = HeaderBuilder()
        b.string("general.architecture", "gemma3")
        b.u32("gemma3.block_count", 26)
        b.u32("gemma3.context_length", 32768)
        b.u32("gemma3.embedding_length", 1152)
        b.u32("gemma3.attention.head_count", 4)
        b.u32("gemma3.attention.head_count_kv", 1)
        b.u32("gemma3.attention.key_length", 256)
        b.u32("gemma3.attention.value_length", 256)
        b.u32("gemma3.attention.sliding_window", 512)
        let memory = try #require(try GGUFHeader.parse(b.build()).memory)
        #expect(memory.fullKVBytesPerToken == 4 * 1024)
        #expect(memory.windowKVBytesPerToken == Int64(22 * 1024))
        #expect(memory.windowTokens == 512)
    }

    @Test func sharedKVLayersKeepNoCacheOfTheirOwn() throws {
        // Gemma 4 E2B: 35 layers, the last 20 reuse earlier K/V. Of the first 15, every fifth layer attends to everything.
        var b = HeaderBuilder()
        b.string("general.architecture", "gemma4")
        b.u32("gemma4.block_count", 35)
        b.u32("gemma4.context_length", 131072)
        b.u32("gemma4.embedding_length", 1536)
        b.u32("gemma4.attention.head_count", 8)
        b.u32("gemma4.attention.head_count_kv", 1)
        b.u32("gemma4.attention.key_length", 512)
        b.u32("gemma4.attention.value_length", 512)
        b.u32("gemma4.attention.key_length_swa", 256)
        b.u32("gemma4.attention.value_length_swa", 256)
        b.u32("gemma4.attention.sliding_window", 512)
        b.u32("gemma4.attention.shared_kv_layers", 20)
        b.boolArray("gemma4.attention.sliding_window_pattern", (0..<35).map { $0 % 5 != 4 })
        let memory = try #require(try GGUFHeader.parse(b.build()).memory)
        #expect(memory.fullKVBytesPerToken == 3 * 2048)
        #expect(memory.windowKVBytesPerToken == Int64(12 * 1024))
        #expect(memory.windowTokens == 512)
    }

    @Test func layersWithoutAttentionAddNothing() throws {
        // A hybrid: KV heads per layer, zero where the layer is recurrent.
        var b = HeaderBuilder()
        b.string("general.architecture", "hybrid")
        b.u32("hybrid.block_count", 4)
        b.u32("hybrid.context_length", 8192)
        b.u32("hybrid.embedding_length", 1024)
        b.u32("hybrid.attention.head_count", 8)
        b.u32Array("hybrid.attention.head_count_kv", [0, 0, 2, 0])
        b.u32("hybrid.attention.key_length", 64)
        b.u32("hybrid.attention.value_length", 64)
        #expect(try GGUFHeader.parse(b.build()).memory?.fullKVBytesPerToken == Int64(2 * (64 + 64) * 2))
    }

    @Test func expertCountsGiveTheActiveShare() throws {
        var b = HeaderBuilder()
        b.string("general.architecture", "moe")
        b.u32("moe.block_count", 24)
        b.u32("moe.context_length", 1_000_000)
        b.u32("moe.embedding_length", 2048)
        b.u32("moe.attention.head_count", 16)
        b.u32("moe.attention.head_count_kv", 4)
        b.u32("moe.expert_count", 128)
        b.u32("moe.expert_used_count", 8)
        let memory = try #require(try GGUFHeader.parse(b.build()).memory)
        #expect(memory.activeFraction == 0.119)
        // The profile built from it is what the planner uses for a file larger than memory.
        let profile = try GGUFHeader.parse(b.build()).profile(fileBytes: 6_880_000_000)
        #expect(profile.activeFraction == 0.119 && profile.fileBytes == 6_880_000_000 && !profile.isEstimated)
    }

    @Test func anArrayThatClaimsMoreElementsThanExistIsRejectedNotTrapped() {
        for element: UInt32 in [4, 10, 8] {
            var b = HeaderBuilder()
            b.string("general.architecture", "qwen3")
            b.array("tokenizer.ggml.scores", element: element, claiming: UInt64.max)
            #expect(throws: GGUFHeaderError.self) { _ = try GGUFHeader.parse(b.build()) }
        }
    }

    @Test func aHostileLayerCountOrSharedLayerCountCannotCrashTheFitCheck() throws {
        var many = HeaderBuilder()
        many.string("general.architecture", "qwen3")
        many.u32("qwen3.block_count", 1_000_000)
        #expect(throws: GGUFHeaderError.self) { _ = try GGUFHeader.parse(many.build()) }

        // A negative shared-layer count used to index past the per-layer lists.
        var negative = HeaderBuilder()
        negative.string("general.architecture", "qwen3")
        negative.u32("qwen3.block_count", 4)
        negative.u32("qwen3.context_length", 4096)
        negative.u32("qwen3.embedding_length", 256)
        negative.u32("qwen3.attention.head_count", 4)
        negative.u32("qwen3.attention.head_count_kv", 4)
        negative.int8("qwen3.attention.shared_kv_layers", -5)
        #expect(try GGUFHeader.parse(negative.build()).memory?.fullKVBytesPerToken == 4 * 4 * (64 + 64) * 2)
    }

    @Test func absurdHeadSizesAreCappedSoTheCacheMathCannotOverflow() throws {
        var b = HeaderBuilder()
        b.string("general.architecture", "qwen3")
        b.u32("qwen3.block_count", 2)
        b.u32("qwen3.context_length", 4096)
        b.u32("qwen3.embedding_length", 256)
        b.u32("qwen3.attention.head_count", 4)
        b.u32("qwen3.attention.head_count_kv", 4_000_000_000)
        b.u32("qwen3.attention.key_length", 4_000_000_000)
        b.u32("qwen3.attention.value_length", 128)
        let bytes = try #require(try GGUFHeader.parse(b.build()).memory?.fullKVBytesPerToken)
        #expect(bytes == 2 * 4096 * (16384 + 128) * 2)
        #expect(bytes * Int64(FitPlanner.maxContext) > 0)
    }

    private func gemmaLikeHeader(withOutputMatrix: Bool) -> Data {
        var b = HeaderBuilder()
        b.string("general.architecture", "qwen3")
        b.u32("qwen3.block_count", 2)
        b.u32("qwen3.context_length", 4096)
        b.u32("qwen3.embedding_length", 256)
        b.u32("qwen3.attention.head_count", 4)
        b.u32("qwen3.attention.head_count_kv", 4)
        // Listed out of order on purpose: sizes come from the sorted offsets.
        b.tensor("blk.0.attn_q.weight", offset: 4000)
        b.tensor("token_embd.weight", offset: 1000)
        b.tensor("per_layer_token_embd.weight", offset: 0)
        b.tensor("blk.0.ffn_up.weight", offset: 4500)
        if withOutputMatrix { b.tensor("output.weight", offset: 3000) }
        return b.build()
    }

    @Test func perLayerEmbeddingsStayOutOfRAMBecauseTheyAreOnlyReadRowByRow() throws {
        let info = try GGUFHeader.parse(gemmaLikeHeader(withOutputMatrix: false))
        #expect(info.lazyBytes == 1000, "per_layer_token_embd spans offsets 0 to 1000")
        let profile = info.profile(fileBytes: 10_000)
        #expect(profile.lazyBytes == 1000 && profile.residentBytes == 9000)
    }

    @Test func tokenEmbeddingsAreLazyOnlyWhenTheOutputMatrixIsAnotherTensor() throws {
        // Tied: the same table runs the output matmul on the GPU, so it is resident. Untied: input only, so it is lazy.
        #expect(try GGUFHeader.parse(gemmaLikeHeader(withOutputMatrix: false)).lazyBytes == 1000)
        #expect(try GGUFHeader.parse(gemmaLikeHeader(withOutputMatrix: true)).lazyBytes == 1000 + 2000)
    }

    @Test func aModelWithoutEmbeddingTablesHasNothingLazy() throws {
        var b = HeaderBuilder()
        b.string("general.architecture", "exotic")
        b.u32("exotic.block_count", 2)
        b.tensor("blk.0.attn_q.weight", offset: 0)
        b.tensor("blk.0.ffn_up.weight", offset: 100)
        let info = try GGUFHeader.parse(b.build())
        #expect(info.lazyBytes == 0 && info.profile(fileBytes: 500).residentBytes == 500)
    }

    @Test func aTensorListThatEndsEarlyAsksForMoreBytesAndAnAbsurdOneIsRejected() throws {
        var b = HeaderBuilder()
        b.string("general.architecture", "qwen3")
        b.tensor("a", offset: 0)
        let whole = b.build()
        #expect(throws: GGUFHeaderError.needMoreData) { _ = try GGUFHeader.parse(whole.prefix(whole.count - 3)) }
        var absurd = Data("GGUF".utf8)
        absurd += withUnsafeBytes(of: UInt32(3).littleEndian) { Data($0) }
        absurd += withUnsafeBytes(of: UInt64(1 << 40).littleEndian) { Data($0) }
        absurd += withUnsafeBytes(of: UInt64(0).littleEndian) { Data($0) }
        #expect(throws: GGUFHeaderError.unsupported("The GGUF header is implausible.")) { _ = try GGUFHeader.parse(absurd) }
    }

    @Test func aHugeTokenTableIsSkippedNotDecoded() throws {
        var b = HeaderBuilder()
        b.string("general.architecture", "qwen3")
        b.stringArray("tokenizer.ggml.tokens", count: 6000)
        b.u32("qwen3.block_count", 2)
        b.u32("qwen3.context_length", 4096)
        b.u32("qwen3.embedding_length", 256)
        b.u32("qwen3.attention.head_count", 4)
        b.u32("qwen3.attention.head_count_kv", 4)
        #expect(try GGUFHeader.parse(b.build()).memory?.fullKVBytesPerToken == Int64(2 * 4 * (64 + 64) * 2))
    }

    @Test func anArchitectureWithoutAttentionKeysFallsBackToAnEstimate() throws {
        var b = HeaderBuilder()
        b.string("general.architecture", "exotic")
        b.u32("exotic.block_count", 24)
        b.u32("exotic.context_length", 65536)
        let info = try GGUFHeader.parse(b.build())
        #expect(info.memory == nil)
        #expect(info.blockCount == 24)
        let profile = info.profile(fileBytes: 1_000_000_000)
        #expect(profile.isEstimated && profile.trainedContext == 65536)
    }

    @Test func aHeaderThatEndsEarlyAsksForMoreBytesAndAnotherFormatIsRejected() throws {
        var b = HeaderBuilder()
        b.string("general.architecture", "qwen3")
        b.u32("qwen3.block_count", 2)
        let whole = b.build()
        #expect(throws: GGUFHeaderError.needMoreData) { _ = try GGUFHeader.parse(whole.prefix(whole.count - 3)) }
        #expect(throws: GGUFHeaderError.notGGUF) { _ = try GGUFHeader.parse(Data("PK\u{3}\u{4}0000".utf8)) }
    }

    @Test func aRemoteHeaderIsReadInGrowingPrefixesUntilItIsComplete() async throws {
        // A vocabulary of 450,000 tokens makes the header about 7.6 MB: more than the first 4 MB prefix.
        var b = HeaderBuilder()
        b.string("general.architecture", "qwen3")
        b.stringArray("tokenizer.ggml.tokens", count: 450_000)
        b.u32("qwen3.block_count", 2)
        b.u32("qwen3.context_length", 4096)
        b.u32("qwen3.embedding_length", 256)
        b.u32("qwen3.attention.head_count", 4)
        b.u32("qwen3.attention.head_count_kv", 4)
        let whole = b.build()
        #expect(whole.count > GGUFHeader.readSizes[0] && whole.count < GGUFHeader.readSizes[1])
        let sizes = SizeLog()
        let info = try await GGUFHeader.read { size in
            await sizes.add(size)
            return whole.prefix(size)
        }
        #expect(info.memory?.fullKVBytesPerToken == Int64(2 * 4 * (64 + 64) * 2))
        #expect(await sizes.sizes == [GGUFHeader.readSizes[0], GGUFHeader.readSizes[1]])
    }

    @Test func aFileThatEndsInsideItsHeaderIsAnErrorNotAnEndlessRead() async {
        var b = HeaderBuilder()
        b.string("general.architecture", "qwen3")
        b.u32("qwen3.block_count", 2)
        let whole = b.build()
        await #expect(throws: GGUFHeaderError.needMoreData) {
            _ = try await GGUFHeader.read { _ in whole.prefix(whole.count - 2) }
        }
    }

    @Test func ggufInfoReadsRepoFilesThroughARangedRequest() async throws {
        var b = HeaderBuilder()
        b.string("general.architecture", "llama")
        b.u32("llama.block_count", 16)
        b.u32("llama.context_length", 131072)
        b.u32("llama.embedding_length", 2048)
        b.u32("llama.attention.head_count", 32)
        b.u32("llama.attention.head_count_kv", 8)
        let header = b.build()
        let http = FakeHTTP { request in
            #expect(request.url?.path == "/org/m-GGUF/resolve/main/m-Q4_K_M.gguf")
            #expect(request.value(forHTTPHeaderField: "Range")?.hasPrefix("bytes=0-") == true)
            return (header, 206)
        }
        let info = try await HuggingFaceAPI(http: http).ggufInfo(repo: "org/m-GGUF", file: "m-Q4_K_M.gguf")
        #expect(info.memory?.fullKVBytesPerToken == 32768 && info.trainedContext == 131072)
        await #expect(throws: LocalModelError.invalidFilePath("../x.gguf")) {
            _ = try await HuggingFaceAPI(http: http).ggufInfo(repo: "org/m-GGUF", file: "../x.gguf")
        }
    }

    @Test func browsingARepoGivesEveryFileTheModelsRealShape() async throws {
        var b = HeaderBuilder()
        b.string("general.architecture", "moe")
        b.u32("moe.block_count", 24)
        b.u32("moe.context_length", 1_000_000)
        b.u32("moe.embedding_length", 2048)
        b.u32("moe.attention.head_count", 16)
        b.u32("moe.attention.head_count_kv", 4)
        b.u32("moe.expert_count", 128)
        b.u32("moe.expert_used_count", 8)
        let header = b.build()
        let listing = #"[{"type":"file","path":"m-IQ1_S.gguf","size":6880000000,"lfs":{"oid":"aa"}},{"type":"file","path":"m-Q4_K_M.gguf","size":15000000000,"lfs":{"oid":"bb"}}]"#
        let probed = LockedList()
        let http = FakeHTTP { request in
            if request.url?.path.contains("/api/models/") == true { return (Data(listing.utf8), 200) }
            probed.append(request.url?.lastPathComponent ?? "")
            return (header, 206)
        }
        let service = CatalogService(
            bundled: { CatalogDocument(schemaVersion: 1, updatedAt: nil, models: []) }, api: HuggingFaceAPI(http: http),
            cacheDirectory: makeTempDirectory(), settings: { CatalogSettings() })
        let entries = try await service.entries(forRepo: "org/m", format: .gguf)
        #expect(entries.count == 2)
        #expect(probed.items == ["m-IQ1_S.gguf"], "only the smallest file's header is read")
        for entry in entries {
            #expect(entry.memory?.activeFraction == 0.119)
            #expect(entry.contextLength == 1_000_000)
        }
        // The big file is judged on its own size with the shared shape: too big for 8 GB, streamed on a big-enough model.
        let profile = try #require(entries.first { $0.file == "m-IQ1_S.gguf" }?.memoryProfile)
        #expect(!profile.isEstimated && profile.fileBytes == 6_880_000_000)
    }

    @Test func aRepoWhoseHeaderCannotBeReadStillListsItsFilesAsEstimates() async throws {
        let listing = #"[{"type":"file","path":"m-Q4_K_M.gguf","size":2000000000,"lfs":{"oid":"bb"}}]"#
        let http = FakeHTTP { request in
            request.url?.path.contains("/api/models/") == true ? (Data(listing.utf8), 200) : (Data(), 404)
        }
        let service = CatalogService(
            bundled: { CatalogDocument(schemaVersion: 1, updatedAt: nil, models: []) }, api: HuggingFaceAPI(http: http),
            cacheDirectory: makeTempDirectory(), settings: { CatalogSettings() })
        let entries = try await service.entries(forRepo: "org/m", format: .gguf)
        #expect(entries.count == 1 && entries[0].memory == nil)
        #expect(entries[0].memoryProfile?.isEstimated == true)
    }

    @Test func readsTheHeaderOfAFileOnDiskAndThePackagedTinyModel() throws {
        var b = HeaderBuilder()
        b.string("general.architecture", "qwen3")
        b.u32("qwen3.block_count", 1)
        b.u32("qwen3.context_length", 512)
        b.u32("qwen3.embedding_length", 64)
        b.u32("qwen3.attention.head_count", 2)
        b.u32("qwen3.attention.head_count_kv", 2)
        let url = makeTempDirectory().appending(path: "tiny.gguf")
        try b.build().write(to: url)
        #expect(try GGUFHeader.read(fileAt: url).memory?.fullKVBytesPerToken == Int64(1 * 2 * (32 + 32) * 2))
    }
}
