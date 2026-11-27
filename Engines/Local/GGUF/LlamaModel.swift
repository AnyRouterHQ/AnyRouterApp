import Foundation
import llama
import Metal

struct LlamaResult: Sendable {
    var promptTokens: Int
    var completionTokens: Int
    /// "stop" when the model ended its answer, "length" when the token or context limit ended it.
    var finishReason: String
}

/// One loaded GGUF model (the weights). Contexts are made per request, so the model can stay loaded between chats.
/// The llama.cpp calls here block, so call them off the main actor.
final class LlamaModel: @unchecked Sendable {
    private static let backend: Void = {
        // No llama.cpp logging: it can echo prompt text.
        llama_log_set({ _, _, _ in }, nil)
        llama_backend_init()
    }()

    private let model: OpaquePointer
    private let vocab: OpaquePointer
    private let name: String
    private let profile: ModelMemoryProfile
    /// The image reader, loaded the first time a photo comes in and kept while the weights are.
    private var vision: (path: String, session: VisionSession)?
    let trainedContext: Int
    /// Context size chosen from the memory this device can give: the largest that fits. A generation lowers it when the
    /// system cannot allocate that much, so the next one starts from what worked.
    private(set) var contextSize: Int
    private let template: String?
    /// The text of the vocabulary's BOS token (for example `<|begin_of_text|>`), nil when it has none.
    private let bosText: String?
    private let eosText: String?
    /// The template compiled once; nil when the model has none or it uses syntax the engine cannot compile.
    private let jinja: JinjaChatTemplate?
    private let thoughtChannel: (open: llama_token, close: llama_token)?
    /// Models whose reasoning is a span of special tokens (Inkling) get `<think>` tags written around it, so the
    /// reasoning row shows it apart from the answer.
    private let thinkingSpan: (open: llama_token, close: llama_token)?

    init(path: String) throws {
        _ = Self.backend
        let name = (path as NSString).lastPathComponent
        // The header tells how much memory the model needs. A file whose header cannot be read still loads, on an estimate.
        let fileBytes = ((try? FileManager.default.attributesOfItem(atPath: path)[.size]) as? NSNumber)?.int64Value ?? 0
        let info = try? GGUFHeader.read(fileAt: URL(fileURLWithPath: path))
        let profile = info?.profile(fileBytes: fileBytes) ?? .estimated(fileBytes: fileBytes, trainedContext: 0)
        let memory = DeviceMemory.current()
        let estimate = FitPlanner.estimate(profile, memory: memory)
        var planned = estimate.context
        #if targetEnvironment(simulator)
        // The Simulator is not limited like a phone, and has no Metal GPU family llama.cpp can use.
        if estimate.verdict == .wontFit { planned = min(max(profile.trainedContext, FitPlanner.minContext), 4096) }
        #else
        if estimate.verdict == .wontFit {
            throw GGUFError.wontFit(name: name, neededBytes: estimate.totalBytes, availableBytes: estimate.deviceBudgetBytes)
        }
        #endif
        var params = llama_model_default_params()
        // Weights are mapped from the file, not copied: pages are loaded on demand and can be dropped under pressure.
        // That is what lets a mixture-of-experts file larger than RAM run. Never mlock: the system must be able to evict.
        params.load_mode = LLAMA_LOAD_MODE_MMAP
        #if targetEnvironment(simulator)
        params.n_gpu_layers = 0
        #else
        if estimate.streamsFromStorage {
            // A streamed model runs on the CPU alone, so only the experts in use are resident. Zero GPU layers is not
            // enough: with the Metal device in the list, llama.cpp still sends long prompts' matrix work to the GPU,
            // which copies weights into memory the system charges to the app. No GPU device (single-device mode with
            // no main GPU) rules that out, and no repacking keeps weights in the mapped file instead of copies.
            params.n_gpu_layers = 0
            params.split_mode = LLAMA_SPLIT_MODE_NONE
            params.main_gpu = -1
            params.use_extra_bufts = false
        } else {
            params.n_gpu_layers = GPUOffload.layers(
                blockCount: info?.blockCount ?? 0, fileBytes: fileBytes,
                gpuBudgetBytes: MTLCreateSystemDefaultDevice().map { Int64($0.recommendedMaxWorkingSetSize) })
        }
        #endif
        LlamaLoadLog.begin()
        let loaded = llama_model_load_from_file(path, params)
        let log = LlamaLoadLog.end()
        guard let model = loaded else {
            throw GGUFError.loadFailed(name: name, reason: LlamaLoadLog.reason(from: log))
        }
        guard let vocab = llama_model_get_vocab(model) else {
            llama_model_free(model)
            throw GGUFError.loadFailed(name: name, reason: "the file has no vocabulary")
        }
        self.model = model
        self.vocab = vocab
        self.name = name
        self.profile = profile
        self.trainedContext = Int(llama_model_n_ctx_train(model))
        self.contextSize = planned
        self.bosText = Self.specialPiece(llama_vocab_bos(vocab), vocab: vocab)
        self.eosText = Self.specialPiece(llama_vocab_eos(vocab), vocab: vocab)
        let template = llama_model_chat_template(model, nil).map { String(cString: $0) }
        self.template = template
        self.jinja = template.flatMap {
            Gemma4Formatter.matches(template: $0) || InklingFormatter.matches(template: $0) ? nil : JinjaChatTemplate(source: $0)
        }
        if let template, Gemma4Formatter.matches(template: template),
           let open = Self.specialToken("<|channel>", vocab: vocab), let close = Self.specialToken("<channel|>", vocab: vocab) {
            self.thoughtChannel = (open, close)
        } else {
            self.thoughtChannel = nil
        }
        if let template, InklingFormatter.matches(template: template),
           let open = Self.specialToken(InklingFormatter.thinking, vocab: vocab),
           let close = Self.specialToken(InklingFormatter.endMessage, vocab: vocab) {
            self.thinkingSpan = (open, close)
        } else {
            self.thinkingSpan = nil
        }
    }

    /// The text of a special token, or nil for "no token".
    private static func specialPiece(_ token: llama_token, vocab: OpaquePointer) -> String? {
        guard token >= 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: 64)
        let count = llama_token_to_piece(vocab, token, &buffer, 64, 0, true)
        guard count > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(count)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    /// The token id when `text` is exactly one special token of the vocabulary, else nil.
    static func specialToken(_ text: String, vocab: OpaquePointer) -> llama_token? {
        var token = llama_token(0)
        let count = llama_tokenize(vocab, text, Int32(text.utf8.count), &token, 1, false, true)
        return count == 1 ? token : nil
    }

    deinit {
        // The image reader points into the model: free it first.
        vision = nil
        llama_model_free(model)
    }

    // MARK: Photos

    /// Tokenizes `text` (one `VisionInput.defaultMarker` per photo) and the photos for this model, loading the projector
    /// at `projectorPath` first when it is not loaded. Throws when the projector does not fit next to the weights.
    func prepareImages(text: String, images: [Data], projectorPath: String) throws -> PreparedVision {
        #if targetEnvironment(simulator)
        let contextCap: Int? = nil
        #else
        var withProjector = profile
        withProjector.projectorBytes = ((try? FileManager.default.attributesOfItem(atPath: projectorPath)[.size]) as? NSNumber)?.int64Value ?? 0
        let memory = DeviceMemory.current()
        let projected = FitPlanner.imageInputEstimate(withProjector, memory: memory)
        guard let estimate = projected, estimate.verdict != .wontFit else {
            throw GGUFError.imagesWontFit(
                name: name, neededBytes: projected?.totalBytes ?? profile.fileBytes, availableBytes: memory.budgetBytes)
        }
        // The context was planned for the weights alone: leave room for the projector.
        let contextCap: Int? = estimate.context
        #endif
        let session: VisionSession
        if let loaded = vision, loaded.path == projectorPath {
            session = loaded.session
        } else {
            vision = nil
            session = try VisionSession(projectorPath: projectorPath, model: model)
            vision = (projectorPath, session)
        }
        return try session.prepare(
            text: text, addSpecial: PromptBuilder.addsSpecialTokens(to: text, bosText: bosText),
            images: images, contextCap: contextCap)
    }

    // MARK: Prompt

    /// Which formatter wrote a prompt, for the smoke report.
    enum PromptPath: String, Sendable { case gemma4, inkling, jinja, native, chatML }

    /// The prompt in the model's own chat format, and which formatter produced it. In order: the Gemma 4 and Inkling
    /// formatters, the model's own template rendered with Jinja, llama.cpp's built-in list of templates, and ChatML as the last resort.
    func format(_ messages: [PromptMessage]) -> (path: PromptPath, text: String) {
        if let template, Gemma4Formatter.matches(template: template) { return (.gemma4, Gemma4Formatter.format(messages)) }
        if let template, InklingFormatter.matches(template: template) { return (.inkling, InklingFormatter.format(messages)) }
        if let rendered = jinja?.render(messages, bos: bosText, eos: eosText) { return (.jinja, rendered) }
        if let native = formatWithTemplate(messages) { return (.native, native) }
        return (.chatML, ChatMLFormatter.format(messages))
    }

    func formatPrompt(_ messages: [PromptMessage]) -> String {
        format(messages).text
    }

    /// For each text: its token id when it is one special token, and whether generation stops on it.
    func stopReport(for texts: [String]) -> String {
        texts.map { text in
            guard let token = Self.specialToken(text, vocab: vocab) else { return "\(text): not a single token" }
            return "\(text): id \(token), \(llama_vocab_is_eog(vocab, token) ? "stops" : "does not stop")"
        }.joined(separator: "; ")
    }

    private func formatWithTemplate(_ messages: [PromptMessage]) -> String? {
        guard let template, !messages.isEmpty else { return nil }
        let owned: [(role: UnsafeMutablePointer<CChar>, content: UnsafeMutablePointer<CChar>)] = messages.map {
            (strdup($0.role)!, strdup($0.content)!)
        }
        defer {
            for pair in owned {
                free(pair.role)
                free(pair.content)
            }
        }
        let chat = owned.map { llama_chat_message(role: UnsafePointer($0.role), content: UnsafePointer($0.content)) }
        let textBytes = messages.reduce(0) { $0 + $1.role.utf8.count + $1.content.utf8.count }
        var capacity = Int32(max(2048, textBytes * 2 + 256))
        var buffer = [CChar](repeating: 0, count: Int(capacity))
        var written = llama_chat_apply_template(template, chat, chat.count, true, &buffer, capacity)
        if written > capacity {
            capacity = written
            buffer = [CChar](repeating: 0, count: Int(capacity))
            written = llama_chat_apply_template(template, chat, chat.count, true, &buffer, capacity)
        }
        guard written > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(written)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    func tokenize(_ text: String) throws -> [llama_token] {
        let byteCount = text.utf8.count
        // Special tokens are parsed (the template writes them as text). BOS is added when the model wants one, unless the
        // template already wrote it.
        let addSpecial = PromptBuilder.addsSpecialTokens(to: text, bosText: bosText)
        var capacity = Int32(byteCount + 8)
        var tokens = [llama_token](repeating: 0, count: Int(capacity))
        var count = llama_tokenize(vocab, text, Int32(byteCount), &tokens, capacity, addSpecial, true)
        if count < 0 {
            capacity = -count
            tokens = [llama_token](repeating: 0, count: Int(capacity))
            count = llama_tokenize(vocab, text, Int32(byteCount), &tokens, capacity, addSpecial, true)
        }
        guard count >= 0 else { throw GGUFError.tokenizeFailed }
        return Array(tokens.prefix(Int(count)))
    }

    private func pieceBytes(_ token: llama_token) -> [UInt8] {
        var capacity: Int32 = 64
        var buffer = [CChar](repeating: 0, count: Int(capacity))
        var count = llama_token_to_piece(vocab, token, &buffer, capacity, 0, false)
        if count < 0 {
            capacity = -count
            buffer = [CChar](repeating: 0, count: Int(capacity))
            count = llama_token_to_piece(vocab, token, &buffer, capacity, 0, false)
        }
        return buffer.prefix(max(0, Int(count))).map { UInt8(bitPattern: $0) }
    }

    // MARK: Generation

    /// Runs the prompt and streams the answer through `emit`. Throws `CancellationError` when `isCancelled` turns true.
    func generate(
        promptTokens: [llama_token], params: GenerationParams, sampling: CatalogSampling? = nil, isCancelled: () -> Bool,
        emit: (String) -> Void
    ) throws -> LlamaResult {
        try generate(
            promptSize: promptTokens.count, batch: 512, contextCap: nil, params: params, sampling: sampling,
            isCancelled: isCancelled, emit: emit
        ) { context, batchSize in
            // Prefill in n_batch sized chunks; only the last token produces logits.
            var tokens = promptTokens
            var offset = 0
            while offset < tokens.count {
                if isCancelled() { throw CancellationError() }
                let count = min(batchSize, tokens.count - offset)
                let start = offset
                let status = tokens.withUnsafeMutableBufferPointer { buffer in
                    llama_decode(context, llama_batch_get_one(buffer.baseAddress! + start, Int32(count)))
                }
                guard status == 0 else { throw GGUFError.decodeFailed(status) }
                offset += count
            }
        }
    }

    /// The answer to a prompt with photos. The photos and the text around them go through `mtmd`, which encodes each photo
    /// into the tokens the model reads.
    func generate(
        images prompt: PreparedVision, params: GenerationParams, sampling: CatalogSampling? = nil,
        isCancelled: () -> Bool, emit: (String) -> Void
    ) throws -> LlamaResult {
        // A photo is read in one piece (up to a few hundred tokens), so the batch must hold it.
        try generate(
            promptSize: prompt.tokenCount, batch: 1024, contextCap: prompt.contextCap, params: params, sampling: sampling,
            isCancelled: isCancelled, emit: emit
        ) { context, batchSize in
            try prompt.evaluate(context: context, batchSize: batchSize)
        }
    }

    /// Creates the context, reads the prompt through `prefill`, then samples until the model stops. `promptSize` is the
    /// number of positions the prompt takes, checked against the context before anything is allocated.
    private func generate(
        promptSize: Int, batch: Int, contextCap: Int?, params: GenerationParams, sampling: CatalogSampling?,
        isCancelled: () -> Bool, emit: (String) -> Void, prefill: (OpaquePointer, Int) throws -> Void
    ) throws -> LlamaResult {
        guard promptSize < contextSize else {
            throw GGUFError.promptTooLong(tokens: promptSize, limit: contextSize)
        }
        var contextParams = llama_context_default_params()
        let threads = Int32(max(1, min(6, ProcessInfo.processInfo.activeProcessorCount - 2)))
        contextParams.n_threads = threads
        contextParams.n_threads_batch = threads
        // Ask for the planned context. When the system cannot allocate that much, halve it until it can.
        var attempt = min(contextSize, contextCap ?? contextSize)
        let planned = attempt
        var created: OpaquePointer?
        while true {
            contextParams.n_ctx = UInt32(attempt)
            contextParams.n_batch = UInt32(min(batch, attempt))
            contextParams.n_ubatch = UInt32(min(batch, attempt))
            created = llama_init_from_model(model, contextParams)
            if created != nil || attempt <= FitPlanner.minContext { break }
            attempt = max(FitPlanner.minContext, attempt / 2 / FitPlanner.contextStep * FitPlanner.contextStep)
        }
        guard let context = created else { throw GGUFError.contextFailed }
        defer { llama_free(context) }
        // Remember a smaller context only when the system forced it, not when a cap for photos set it.
        if attempt < planned { contextSize = attempt }
        guard promptSize < attempt else {
            throw GGUFError.promptTooLong(tokens: promptSize, limit: attempt)
        }
        let sampler = Self.makeSampler(params, topK: sampling?.topK ?? 40, minP: sampling?.minP ?? 0)
        defer { llama_sampler_free(sampler) }

        try prefill(context, Int(contextParams.n_batch))

        var generated = 0
        var reason = "length"
        var accumulator = UTF8Accumulator()
        var thought = ThoughtChannelFilter(open: thoughtChannel?.open, close: thoughtChannel?.close)
        var span = ThinkingSpanTagger(open: thinkingSpan?.open, close: thinkingSpan?.close)
        let limit = params.maxTokens ?? Int.max
        while generated < limit {
            if isCancelled() { throw CancellationError() }
            var token = llama_sampler_sample(sampler, context, -1)
            if llama_vocab_is_eog(vocab, token) {
                reason = "stop"
                break
            }
            generated += 1
            if let tag = span.tag(for: token) {
                if let text = accumulator.flush() { emit(text) }
                emit(tag)
            } else if thought.isVisible(token), let text = accumulator.append(pieceBytes(token)) {
                emit(text)
            }
            let status = withUnsafeMutablePointer(to: &token) { pointer in
                llama_decode(context, llama_batch_get_one(pointer, 1))
            }
            if status == 1 { break } // no room left in the context
            guard status == 0 else { throw GGUFError.decodeFailed(status) }
        }
        if let tail = accumulator.flush() { emit(tail) }
        return LlamaResult(promptTokens: promptSize, completionTokens: generated, finishReason: reason)
    }

    /// `topK` 0 and `minP` 0 leave those filters out.
    private static func makeSampler(_ params: GenerationParams, topK: Int, minP: Double) -> UnsafeMutablePointer<llama_sampler> {
        let chain = llama_sampler_chain_init(llama_sampler_chain_default_params())!
        if params.temperature <= 0 {
            llama_sampler_chain_add(chain, llama_sampler_init_greedy())
        } else {
            if topK > 0 { llama_sampler_chain_add(chain, llama_sampler_init_top_k(Int32(clamping: topK))) }
            llama_sampler_chain_add(chain, llama_sampler_init_top_p(Float(params.topP), 1))
            if minP > 0 { llama_sampler_chain_add(chain, llama_sampler_init_min_p(Float(minP), 1)) }
            llama_sampler_chain_add(chain, llama_sampler_init_temp(Float(params.temperature)))
            llama_sampler_chain_add(chain, llama_sampler_init_dist(UInt32.random(in: .min ... .max)))
        }
        return chain
    }
}
