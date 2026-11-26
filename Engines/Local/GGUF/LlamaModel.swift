import Foundation
import llama

struct LlamaResult: Sendable {
    var promptTokens: Int
    var completionTokens: Int
    /// "stop" when the model ended its answer, "length" when the token or context limit ended it.
    var finishReason: String
}

/// One loaded GGUF model (the weights). Contexts are made per request, so the model can stay loaded between chats.
/// The llama.cpp calls here block, so call them off the main actor.
final class LlamaModel: @unchecked Sendable {
    /// Largest context the app asks for, to bound KV-cache memory on a phone.
    static let maxContext = 4096

    private static let backend: Void = {
        // No llama.cpp logging: it can echo prompt text.
        llama_log_set({ _, _, _ in }, nil)
        llama_backend_init()
    }()

    private let model: OpaquePointer
    private let vocab: OpaquePointer
    let trainedContext: Int
    private let template: String?

    init(path: String) throws {
        _ = Self.backend
        var params = llama_model_default_params()
        #if targetEnvironment(simulator)
        // The simulator has no Metal GPU family llama.cpp can use.
        params.n_gpu_layers = 0
        #endif
        guard let model = llama_model_load_from_file(path, params) else {
            throw GGUFError.loadFailed((path as NSString).lastPathComponent)
        }
        guard let vocab = llama_model_get_vocab(model) else {
            llama_model_free(model)
            throw GGUFError.loadFailed((path as NSString).lastPathComponent)
        }
        self.model = model
        self.vocab = vocab
        self.trainedContext = Int(llama_model_n_ctx_train(model))
        if let raw = llama_model_chat_template(model, nil) {
            self.template = String(cString: raw)
        } else {
            self.template = nil
        }
    }

    deinit {
        llama_model_free(model)
    }

    /// Context size to use: the model's own limit, capped by `maxContext`.
    var contextSize: Int {
        max(256, min(trainedContext > 0 ? trainedContext : Self.maxContext, Self.maxContext))
    }

    // MARK: Prompt

    /// The prompt in the model's own chat format. Uses the template stored in the GGUF; ChatML when llama.cpp cannot apply it.
    func formatPrompt(_ messages: [PromptMessage]) -> String {
        formatWithTemplate(messages) ?? ChatMLFormatter.format(messages)
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
        // Special tokens are parsed (the template writes them as text); BOS is added when the model wants one.
        var capacity = Int32(byteCount + 8)
        var tokens = [llama_token](repeating: 0, count: Int(capacity))
        var count = llama_tokenize(vocab, text, Int32(byteCount), &tokens, capacity, true, true)
        if count < 0 {
            capacity = -count
            tokens = [llama_token](repeating: 0, count: Int(capacity))
            count = llama_tokenize(vocab, text, Int32(byteCount), &tokens, capacity, true, true)
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
        promptTokens: [llama_token], params: GenerationParams, isCancelled: () -> Bool, emit: (String) -> Void
    ) throws -> LlamaResult {
        let contextSize = self.contextSize
        guard promptTokens.count < contextSize else {
            throw GGUFError.promptTooLong(tokens: promptTokens.count, limit: contextSize)
        }
        var contextParams = llama_context_default_params()
        contextParams.n_ctx = UInt32(contextSize)
        contextParams.n_batch = UInt32(min(512, contextSize))
        contextParams.n_ubatch = UInt32(min(512, contextSize))
        let threads = Int32(max(1, min(6, ProcessInfo.processInfo.activeProcessorCount - 2)))
        contextParams.n_threads = threads
        contextParams.n_threads_batch = threads
        guard let context = llama_init_from_model(model, contextParams) else { throw GGUFError.contextFailed }
        defer { llama_free(context) }
        let sampler = Self.makeSampler(params)
        defer { llama_sampler_free(sampler) }

        // Prefill in n_batch sized chunks; only the last token produces logits.
        var tokens = promptTokens
        let batchSize = Int(contextParams.n_batch)
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

        var generated = 0
        var reason = "length"
        var accumulator = UTF8Accumulator()
        let limit = params.maxTokens ?? Int.max
        while generated < limit {
            if isCancelled() { throw CancellationError() }
            var token = llama_sampler_sample(sampler, context, -1)
            if llama_vocab_is_eog(vocab, token) {
                reason = "stop"
                break
            }
            generated += 1
            if let text = accumulator.append(pieceBytes(token)) { emit(text) }
            let status = withUnsafeMutablePointer(to: &token) { pointer in
                llama_decode(context, llama_batch_get_one(pointer, 1))
            }
            if status == 1 { break } // no room left in the context
            guard status == 0 else { throw GGUFError.decodeFailed(status) }
        }
        if let tail = accumulator.flush() { emit(tail) }
        return LlamaResult(promptTokens: promptTokens.count, completionTokens: generated, finishReason: reason)
    }

    private static func makeSampler(_ params: GenerationParams) -> UnsafeMutablePointer<llama_sampler> {
        let chain = llama_sampler_chain_init(llama_sampler_chain_default_params())!
        if params.temperature <= 0 {
            llama_sampler_chain_add(chain, llama_sampler_init_greedy())
        } else {
            llama_sampler_chain_add(chain, llama_sampler_init_top_k(40))
            llama_sampler_chain_add(chain, llama_sampler_init_top_p(Float(params.topP), 1))
            llama_sampler_chain_add(chain, llama_sampler_init_temp(Float(params.temperature)))
            llama_sampler_chain_add(chain, llama_sampler_init_dist(UInt32.random(in: .min ... .max)))
        }
        return chain
    }
}
