import UIKit
import XCTest

@testable import AnyRouter

/// Runs one bundled GGUF model (the smallest, or `ANYROUTER_SMOKE_MODEL_ID`) through the real `GGUFEngine` path: catalog entry, installer, llama.cpp.
/// Skipped unless `ANYROUTER_SMOKE_GGUF_PATH` is set, so normal CI stays fast.
final class GGUFModelSmokeTests: XCTestCase {
    struct Context {
        var engine: GGUFEngine
        var storage: LocalModelStorage
        var entry: CatalogEntry
        var model: ModelDescriptor
        var sourceFile: URL
        var sha256: String
        var size: Int64
        var attachments: AttachmentStore
    }

    /// A hard link when possible: a multi-GB model must not take twice the runner's disk.
    static func stage(_ source: URL, as destination: URL) throws {
        do { try FileManager.default.linkItem(at: source, to: destination) } catch {
            try FileManager.default.copyItem(at: source, to: destination)
        }
    }

    static func makeContext(withProjector: Bool = false) async throws -> Context {
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
        XCTAssertEqual(source.lastPathComponent, (file as NSString).lastPathComponent, "the workflow must download the chosen GGUF file")
        XCTAssertEqual(size, entry.sizeBytes, "catalog sizeBytes must match the real file")

        let storage = LocalModelStorage(root: makeTempDirectory())
        let partial = storage.partialFileURL(forEntryID: entry.id, path: file)
        try FileManager.default.createDirectory(at: partial.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.stage(source, as: partial)
        var installed = [HFFile(path: file, size: size, sha256: sha)]
        var addOnJob: DownloadJobRecord?
        if withProjector {
            // The projector sits next to the model file. The workflow downloaded it and checked its sha256.
            let name = try XCTUnwrap(SmokeEnv.mmprojFile, "the workflow gave no projector for this model")
            let projector = source.deletingLastPathComponent().appending(path: name)
            let projectorSize = try XCTUnwrap(try FileManager.default.attributesOfItem(atPath: projector.path)[.size] as? NSNumber).int64Value
            let projectorFile = HFFile(path: name, size: projectorSize, sha256: SmokeEnv.mmprojSHA256)
            // An optional projector installs the way "Add photo support" does: a download of its own, after the model.
            let owner = entry.photoAddOn
            let projectorPartial = storage.partialFileURL(forEntryID: owner?.id ?? entry.id, path: name)
            try FileManager.default.createDirectory(at: projectorPartial.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Self.stage(projector, as: projectorPartial)
            if let owner { addOnJob = DownloadJobRecord(entry: owner, files: [projectorFile]) } else { installed.append(projectorFile) }
        }
        try ModelInstaller.verifyAndInstall(DownloadJobRecord(entry: entry, files: installed), storage: storage)
        XCTAssertTrue(storage.isInstalled(entryID: entry.id))
        if let addOnJob {
            try ModelInstaller.verifyAndInstall(addOnJob, storage: storage)
            XCTAssertTrue(storage.isInstalled(entryID: addOnJob.entry.id))
        }

        let catalog = CatalogService(
            bundled: { document }, cacheDirectory: makeTempDirectory(), settings: { CatalogSettings() })
        let attachments = AttachmentStore(root: makeTempDirectory())
        let engine = GGUFEngine(storage: storage, catalog: catalog, attachments: attachments)
        let models = try await engine.availableModels()
        let model = try XCTUnwrap(models.first { $0.id == entry.id }, "engine must list the installed catalog model")
        XCTAssertTrue(model.isInstalled)
        return Context(engine: engine, storage: storage, entry: entry, model: model, sourceFile: source, sha256: sha, size: size, attachments: attachments)
    }

    /// A solid red square as a JPEG: a photo no model can mistake, and no fixture file in the repo.
    private static func redPhoto(side: Int = 448) -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return format
        }())
        return renderer.jpegData(withCompressionQuality: 0.9) { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        }
    }

    /// Qwen3 thinks first. The answer is what follows `</think>`.
    private static func answer(from text: String) -> String {
        let tail = text.range(of: "</think>").map { String(text[$0.upperBound...]) } ?? text
        return tail.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func testAnswersTwoPlusTwoWithUsageAndDone() async throws {
        let ctx = try await Self.makeContext()
        var params = GenerationParams()
        params.temperature = 0
        params.maxTokens = SmokeEnv.maxTokens ?? 1024

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
            case .toolCall, .toolResult, .metadata, .reasoning:
                break
            }
        }
        let end = clock.now

        XCTAssertFalse(text.isEmpty, "stream produced no text")
        let answer = Self.answer(from: text)
        // finish "length" means the token budget ran out, often inside the thinking block: rerun with a larger max_tokens.
        XCTAssertTrue(answer.contains("4"), "final answer after the thinking block must contain 4 (finish \(finishReason ?? "nil")), got: \(SmokeEnv.external ? "(not printed for a model given at run time)" : answer)")
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
        if let report = await ctx.engine.promptReport(
            model: ctx.model, stopTexts: ["</s>", "<s>", "<eos>", "<bos>", "<|im_start|>", "<|im_end|>", "<|endoftext|>", "<turn|>"]) {
            SmokeReport.record("GGUF prompt format", report.path)
            // A model given at run time may be private: its rendered prompt and special-token names would fingerprint it.
            if !SmokeEnv.external {
                SmokeReport.record("GGUF prompt for \"hi\"", report.prompt.replacingOccurrences(of: "\n", with: "\\n"))
                SmokeReport.record("GGUF special tokens", report.stops)
            }
        }
        SmokeReport.record("App memory after the answer", FitFormat.gigabytes(MemoryReading.footprintBytes()))
        SmokeReport.record("GGUF prompt", "What is 2+2? Answer with one number.")
        if SmokeEnv.external {
            SmokeReport.record("GGUF answer", answer.contains("4") ? "contains 4 (text not printed for a model given at run time)" : "does not contain 4")
        } else {
            SmokeReport.record("GGUF answer", answer)
            SmokeReport.record("GGUF raw output", String(text.prefix(300)))
        }
        SmokeReport.record("GGUF tokens", "prompt \(reported.prompt), completion \(reported.completion), finish \(finishReason ?? "nil")")
        SmokeReport.record("GGUF load + first token", firstText.map { String(format: "%.2f s", seconds($0 - start)) } ?? "n/a")
        if reported.completion >= 8 { SmokeReport.record("GGUF tokens/sec (decode)", String(format: "%.1f", perSecond)) }
    }

    /// The eval prompt for a device run too: a photo of one flat color, asked for its name.
    /// Agent v2 U1: decoded over prompt for each turn of a 3-turn chat. Every request prefills its whole prompt today, so
    /// each turn reads 1.00; this is the baseline a kept context (U11) must bring to 0.35 or less on turns 2 and 3.
    func testDecodedOverPromptForEachTurnOfAChat() async throws {
        let ctx = try await Self.makeContext()
        var params = GenerationParams()
        params.temperature = 0
        params.maxTokens = 32
        var messages: [ChatMessage] = []
        var ratios: [String] = []
        for question in ["Name a fruit.", "Name a color.", "Name an animal."] {
            messages.append(ChatMessage(role: .user, content: question))
            var reply = ""
            var prompt = 0
            var decoded: Int?
            for try await delta in ctx.engine.stream(model: ctx.model, messages: messages, params: params) {
                switch delta {
                case .text(let piece): reply += piece
                case .usage(let tokens, _): prompt = tokens
                case .metadata(let metadata): decoded = metadata.decodedTokens
                default: break
                }
            }
            let count = try XCTUnwrap(decoded, "the engine reports what it decoded")
            XCTAssertGreaterThan(prompt, 0)
            XCTAssertLessThanOrEqual(count, prompt)
            ratios.append(String(format: "%.2f", Double(count) / Double(prompt)) + " (\(count)/\(prompt))")
            messages.append(ChatMessage(role: .assistant, content: reply))
        }
        SmokeReport.record("GGUF decoded/prompt per turn", ratios.joined(separator: ", "))
    }

    func testNamesTheColorOfAPhoto() async throws {
        try XCTSkipUnless(SmokeEnv.mmprojFile != nil, "this model has no image projector")
        let ctx = try await Self.makeContext(withProjector: true)
        // The engine lists "vision" for an installed model whose projector is on disk and that this device has room for.
        // The runner's memory decides the second part, and it moves between two readings, so it is reported, not asserted:
        // the projector state is judged with plenty of room.
        XCTAssertNotNil(
            ctx.storage.projectorURL(forEntryID: ctx.entry.id, addOn: ctx.entry.photoAddOn), "the staged projector must be on disk")
        let roomy = DeviceMemory(budgetBytes: 64_000_000_000, physicalBytes: 64_000_000_000)
        let withRoom = LocalModelDescriptors.installed(format: .gguf, storage: ctx.storage, catalog: [ctx.entry], memory: roomy)
        XCTAssertEqual(
            withRoom.first { $0.id == ctx.entry.id }?.capabilities.contains("vision"), true,
            "an installed model with its projector on disk must list the vision capability")
        SmokeReport.record(
            "Vision capability on this runner",
            ctx.model.capabilities.contains("vision") ? "listed" : "not listed (no room for the projector on this runner)")
        let data = Self.redPhoto()
        let id = UUID()
        let relative = try ctx.attachments.write(data, id: id, fileExtension: "jpg")
        let photo = ChatAttachment(
            id: id, kind: .image, filename: "red.jpg", utType: "public.jpeg", byteCount: Int64(data.count), relativePath: relative)
        var message = ChatMessage(role: .user, content: "What color is this image? Answer with one word.")
        message.attachments = [photo]
        var params = GenerationParams()
        params.temperature = 0
        params.maxTokens = SmokeEnv.maxTokens ?? 1024

        let clock = ContinuousClock()
        let start = clock.now
        var text = ""
        var usage: (prompt: Int, completion: Int)?
        for try await delta in ctx.engine.stream(model: ctx.model, messages: [message], params: params) {
            switch delta {
            case .text(let piece): text += piece
            case .usage(let prompt, let completion): usage = (prompt, completion)
            case .done, .toolCall, .toolResult, .metadata, .reasoning: break
            }
        }
        let elapsed = clock.now - start
        let answer = Self.answer(from: text)
        XCTAssertTrue(answer.lowercased().contains("red"), "the model must name the color of a red photo, got: \(answer)")
        let reported = try XCTUnwrap(usage, "no .usage delta")
        XCTAssertGreaterThan(reported.prompt, VisionInput.tokensPerImage / 4, "the photo must add tokens to the prompt")
        SmokeReport.record("GGUF image prompt", "What color is this image? Answer with one word. (solid red 448x448 JPEG)")
        SmokeReport.record("GGUF image answer", answer)
        SmokeReport.record("GGUF image tokens", "prompt \(reported.prompt), completion \(reported.completion)")
        SmokeReport.record("GGUF image load + answer", String(format: "%.1f s", Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18))
        SmokeReport.record("App memory after the photo", FitFormat.gigabytes(MemoryReading.footprintBytes()))
    }

    func testCancellingMidStreamStopsWithinTwoSeconds() async throws {
        let ctx = try await Self.makeContext()
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
        // Cancel is checked before every decode step, so it lands within one step. A model that decodes under one token
        // a second on the Simulator CPU (a 1-bit 26B ran at 0.2) gets one and a half steps; others keep the 2 s limit.
        let step = firstPieceAt.flatMap { first in markAt.map { seconds($0 - first) / Double(rateMark - 1) } } ?? 0
        let limit = max(2.0, 1.5 * step)
        XCTAssertLessThan(latency, limit, "cancel must stop generation within \(limit)s, took \(latency)s")
        if let firstPieceAt, let markAt, markAt > firstPieceAt {
            SmokeReport.record("GGUF tokens/sec (decode, long story)", String(format: "%.1f (pieces %d to %d)", Double(rateMark - 1) / seconds(markAt - firstPieceAt), 1, rateMark))
        }
        SmokeReport.record("GGUF cancel", String(format: "stopped %.2f s after cancel (limit %.2f s); next chat done %.2f s after cancel, warm baseline %.2f s", latency, limit, total, baseline))
    }

    func testInstallerRejectsWrongChecksumAndWrongSize() async throws {
        let ctx = try await Self.makeContext()
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
