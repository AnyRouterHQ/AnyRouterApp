import XCTest

@testable import AnyRouter

/// Runs one bundled GGUF model (the smallest, or `ANYROUTER_SMOKE_MODEL_ID`) through the real `GGUFEngine` path: catalog entry, installer, llama.cpp.
/// Skipped unless `ANYROUTER_SMOKE_GGUF_PATH` is set, so normal CI stays fast.
final class GGUFModelSmokeTests: XCTestCase {
    private struct Context {
        var engine: GGUFEngine
        var storage: LocalModelStorage
        var entry: CatalogEntry
        var model: ModelDescriptor
        var sourceFile: URL
        var sha256: String
        var size: Int64
    }

    /// A hard link when possible: a multi-GB model must not take twice the runner's disk.
    private static func stage(_ source: URL, as destination: URL) throws {
        do { try FileManager.default.linkItem(at: source, to: destination) } catch {
            try FileManager.default.copyItem(at: source, to: destination)
        }
    }

    private func makeContext() async throws -> Context {
        let path = SmokeEnv.ggufPath
        try XCTSkipUnless(path != nil, "ANYROUTER_SMOKE_GGUF_PATH is not set. The real-model test runs only in model-smoke.yml.")
        let sha = try XCTUnwrap(SmokeEnv.ggufSHA256, "ANYROUTER_SMOKE_GGUF_SHA256 is required with the path")
        let source = URL(fileURLWithPath: try XCTUnwrap(path))

        let size = try XCTUnwrap(try FileManager.default.attributesOfItem(atPath: source.path)[.size] as? NSNumber).int64Value
        let document: CatalogDocument
        let entry: CatalogEntry
        if let json = SmokeEnv.entryJSON {
            // The workflow resolved the entry (catalog, dev catalog or a model given at run time). Nothing here names it.
            entry = try JSONDecoder().decode(CatalogEntry.self, from: Data(json.utf8))
            document = CatalogDocument(schemaVersion: 1, updatedAt: nil, models: [entry])
        } else {
            document = try BundledCatalog.load()
            let ggufs = document.models.filter { $0.format == .gguf }
            entry = try XCTUnwrap(ggufs.min { ($0.sizeBytes ?? .max) < ($1.sizeBytes ?? .max) }, "bundled catalog has no GGUF entry")
        }
        let file = try XCTUnwrap(entry.file)
        XCTAssertEqual(source.lastPathComponent, file, "the workflow must download the chosen GGUF file")
        XCTAssertEqual(size, entry.sizeBytes, "catalog sizeBytes must match the real file")

        let storage = LocalModelStorage(root: makeTempDirectory())
        let partial = storage.partialFileURL(forEntryID: entry.id, path: file)
        try FileManager.default.createDirectory(at: partial.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.stage(source, as: partial)
        try ModelInstaller.verifyAndInstall(
            DownloadJobRecord(entry: entry, files: [HFFile(path: file, size: size, sha256: sha)]), storage: storage)
        XCTAssertTrue(storage.isInstalled(entryID: entry.id))

        let catalog = CatalogService(
            bundled: { document }, cacheDirectory: makeTempDirectory(), settings: { CatalogSettings() })
        let engine = GGUFEngine(storage: storage, catalog: catalog)
        let models = try await engine.availableModels()
        let model = try XCTUnwrap(models.first { $0.id == entry.id }, "engine must list the installed catalog model")
        XCTAssertTrue(model.isInstalled)
        return Context(engine: engine, storage: storage, entry: entry, model: model, sourceFile: source, sha256: sha, size: size)
    }

    /// Qwen3 thinks first. The answer is what follows `</think>`.
    private static func answer(from text: String) -> String {
        let tail = text.range(of: "</think>").map { String(text[$0.upperBound...]) } ?? text
        return tail.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func testAnswersTwoPlusTwoWithUsageAndDone() async throws {
        let ctx = try await makeContext()
        var params = GenerationParams()
        params.temperature = 0
        params.maxTokens = 1024

        let clock = ContinuousClock()
        let start = clock.now
        var firstText: ContinuousClock.Instant?
        var text = ""
        var usage: (prompt: Int, completion: Int)?
        var done = 0
        var finishReason: String?
        var usageBeforeDone = false
        let messages = [ChatMessage(role: .user, content: "What is 2+2? Answer with one number.")]
        for try await delta in ctx.engine.stream(model: ctx.model, messages: messages, params: params) {
            switch delta {
            case .text(let piece):
                if firstText == nil { firstText = clock.now }
                text += piece
            case .usage(let prompt, let completion):
                usage = (prompt, completion)
                usageBeforeDone = done == 0
            case .done(let reason):
                done += 1
                finishReason = reason
            }
        }
        let end = clock.now

        XCTAssertFalse(text.isEmpty, "stream produced no text")
        let answer = Self.answer(from: text)
        XCTAssertTrue(answer.contains("4"), "final answer after the thinking block must contain 4, got: \(answer)")
        XCTAssertEqual(done, 1, "exactly one .done")
        XCTAssertTrue(usageBeforeDone, ".usage arrives before .done")
        let reported = try XCTUnwrap(usage, "no .usage delta")
        XCTAssertGreaterThan(reported.prompt, 0)
        XCTAssertGreaterThan(reported.completion, 0)

        func seconds(_ d: Duration) -> Double { Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18 }
        let total = seconds(end - start)
        let decode = firstText.map { seconds(end - $0) } ?? total
        let perSecond = decode > 0 ? Double(max(reported.completion - 1, 1)) / decode : 0
        SmokeReport.record("GGUF model", SmokeEnv.external
            ? "external model given at run time (not named here), \(ctx.size) bytes"
            : "\(ctx.entry.title) \(ctx.entry.quantization ?? "") (\(ctx.entry.id), rev \((ctx.entry.revision ?? "main").prefix(8)))")
        SmokeReport.record("GGUF file size", "\(ctx.size) bytes, sha256 \(ctx.sha256.prefix(12))")
        SmokeReport.record("GGUF prompt", "What is 2+2? Answer with one number.")
        SmokeReport.record("GGUF answer", answer)
        SmokeReport.record("GGUF raw output", String(text.prefix(300)))
        SmokeReport.record("GGUF tokens", "prompt \(reported.prompt), completion \(reported.completion), finish \(finishReason ?? "nil")")
        SmokeReport.record("GGUF load + first token", firstText.map { String(format: "%.2f s", seconds($0 - start)) } ?? "n/a")
        if reported.completion >= 8 { SmokeReport.record("GGUF tokens/sec (decode)", String(format: "%.1f", perSecond)) }
    }

    func testCancellingMidStreamStopsWithinTwoSeconds() async throws {
        let ctx = try await makeContext()
        var long = GenerationParams()
        long.temperature = 0.8
        long.maxTokens = 2000
        let messages = [ChatMessage(role: .user, content: "Write a very long story about a dragon.")]

        // Baseline: how long a one-token chat takes on a warm engine. Cancel latency is whatever comes on top.
        var short = GenerationParams()
        short.temperature = 0
        short.maxTokens = 1
        func oneTokenChat() async throws -> Bool {
            var sawDone = false
            for try await delta in ctx.engine.stream(
                model: ctx.model, messages: [ChatMessage(role: .user, content: "Hi")], params: short) {
                if case .done = delta { sawDone = true }
            }
            return sawDone
        }
        func seconds(_ d: Duration) -> Double { Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18 }
        let clock = ContinuousClock()
        let baselineStart = clock.now
        let baselineDone = try await oneTokenChat()
        let baseline = seconds(clock.now - baselineStart)
        XCTAssertTrue(baselineDone)

        // The stream starts generating as soon as it is created, so create it only after the baseline chat is done.
        // Timestamps of the first and the 20th text piece give the decode rate.
        let stream = ctx.engine.stream(model: ctx.model, messages: messages, params: long)
        let rateMark = 20
        let reached = AsyncStream<ContinuousClock.Instant>.makeStream()
        let consumer = Task { () -> Int in
            var pieces = 0
            do {
                for try await delta in stream {
                    if case .text = delta {
                        pieces += 1
                        if pieces == 1 || pieces == rateMark { reached.continuation.yield(clock.now) }
                    }
                }
            } catch {}
            reached.continuation.finish()
            return pieces
        }
        var iterator = reached.stream.makeAsyncIterator()
        let firstPieceAt = await iterator.next()
        let markAt = await iterator.next()

        let cancelledAt = clock.now
        consumer.cancel()
        let pieces = await consumer.value
        XCTAssertGreaterThanOrEqual(pieces, rateMark, "generation must have started before the cancel")

        // The engine runs one generation at a time. A new chat only completes if the cancelled one really stopped.
        let sawDone = try await oneTokenChat()
        let total = seconds(clock.now - cancelledAt)
        let latency = max(0, total - baseline)
        XCTAssertTrue(sawDone, "the next chat must complete after the cancel")
        XCTAssertLessThan(latency, 2.0, "cancel must stop generation within 2s, took \(latency)s")
        if let firstPieceAt, let markAt, markAt > firstPieceAt {
            SmokeReport.record("GGUF tokens/sec (decode, long story)", String(format: "%.1f (pieces %d to %d)", Double(rateMark - 1) / seconds(markAt - firstPieceAt), 1, rateMark))
        }
        SmokeReport.record("GGUF cancel", String(format: "stopped %.2f s after cancel (limit 2 s); next chat done %.2f s after cancel, warm baseline %.2f s", latency, total, baseline))
    }

    func testInstallerRejectsWrongChecksumAndWrongSize() async throws {
        let ctx = try await makeContext()
        let id = ctx.entry.id
        let file = try XCTUnwrap(ctx.entry.file)
        let storage = LocalModelStorage(root: makeTempDirectory())
        let partial = storage.partialFileURL(forEntryID: id, path: file)

        func stage() throws {
            try FileManager.default.createDirectory(at: partial.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Self.stage(ctx.sourceFile, as: partial)
        }

        try stage()
        let wrongSHA = String(repeating: "0", count: 64)
        XCTAssertThrowsError(try ModelInstaller.verifyAndInstall(
            DownloadJobRecord(entry: ctx.entry, files: [HFFile(path: file, size: ctx.size, sha256: wrongSHA)]), storage: storage)
        ) { XCTAssertEqual($0 as? LocalModelError, .checksumMismatch(file)) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: partial.path), "a bad file is deleted so a retry fetches it again")
        XCTAssertFalse(storage.isInstalled(entryID: id))

        try stage()
        XCTAssertThrowsError(try ModelInstaller.verifyAndInstall(
            DownloadJobRecord(entry: ctx.entry, files: [HFFile(path: file, size: ctx.size + 1, sha256: ctx.sha256)]), storage: storage)
        ) { XCTAssertEqual($0 as? LocalModelError, .sizeMismatch(file)) }
        XCTAssertFalse(storage.isInstalled(entryID: id))
        SmokeReport.record("Installer", "size and sha256 verified on the cached file; wrong sha256 and wrong size rejected and deleted")
    }
}
