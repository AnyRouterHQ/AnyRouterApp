import Testing
@testable import AnyRouter

/// A load that fails on the phone must say why on screen: the mmap error, not llama.cpp's closing summary line.
struct LlamaLoadLogTests {
    private func warn(_ text: String) -> LlamaLoadLog.Line { LlamaLoadLog.Line(isError: false, text: text) }
    private func error(_ text: String) -> LlamaLoadLog.Line { LlamaLoadLog.Line(isError: true, text: text) }

    /// The shape of a real failed load: details, the cause, then the generic summary llama.cpp always prints last.
    private var failedLoad: [LlamaLoadLog.Line] {
        [
            warn("llama_model_loader: loaded meta data with 40 key-value pairs\n"),
            warn("warning: failed to mlock 1024-byte buffer\n"),
            error("llama_model_load: error loading model: mmap failed: Cannot allocate memory (/var/mobile/Containers/Data/Application/ABC/Library/Models/x/Inkling-2-Mini-AD-IQ1_S.gguf)\n"),
            error("llama_model_load_from_file_impl: failed to load model\n"),
        ]
    }

    @Test func theCauseWinsOverTheClosingSummaryWithThePathCutToTheFileName() {
        #expect(LlamaLoadLog.reason(from: failedLoad)
            == "llama_model_load: error loading model: mmap failed: Cannot allocate memory (Inkling-2-Mini-AD-IQ1_S.gguf)")
    }

    @Test func withoutTheCauseLineTheFirstErrorThatIsNotTheSummaryIsTheReason() {
        let lines = [
            warn("load_tensors: tensor 'blk.0.ffn' has wrong shape\n"),
            error("ggml_backend_cpu_buffer_type_alloc_buffer: failed to allocate buffer of size 7000000000\n"),
            error("llama_model_load_from_file_impl: failed to load model\n"),
        ]
        #expect(LlamaLoadLog.reason(from: lines) == "ggml_backend_cpu_buffer_type_alloc_buffer: failed to allocate buffer of size 7000000000")
        #expect(LlamaLoadLog.reason(from: [error("llama_model_load_from_file_impl: failed to load model")])
            == "llama_model_load_from_file_impl: failed to load model", "the summary when it is all there is")
    }

    @Test func withoutAnErrorLineTheLastLineIsKeptAndSilenceGivesNoReason() {
        #expect(LlamaLoadLog.reason(from: [warn("tensor 'x' has 6/8 rows\n"), warn("  \n")]) == "tensor 'x' has 6/8 rows")
        #expect(LlamaLoadLog.reason(from: []) == nil)
        #expect(LlamaLoadLog.reason(from: [warn("\n"), warn(" ")]) == nil)
    }

    @Test func aLongLineIsCut() {
        #expect(LlamaLoadLog.reason(from: [error(String(repeating: "e", count: 1000))])?.count == 300)
    }

    @Test func theTrailKeepsTheLastTwentyLinesWithShortPaths() {
        let many = (0..<30).map { warn("line \($0) /var/mobile/Models/m.gguf") }
        let trail = LlamaLoadLog.trail(from: many)
        #expect(trail.count == LlamaLoadLog.trailLength)
        #expect(trail.first == "line 10 m.gguf" && trail.last == "line 29 m.gguf")
    }

    @Test func theMessageQuotesLlamaAndCarriesTheLogForDetails() {
        #expect(GGUFError.loadFailed(name: "m.gguf", reason: "mmap failed").errorDescription
            == "Could not load m.gguf. llama.cpp said: mmap failed")
        #expect(GGUFError.loadFailed(name: "m.gguf", reason: nil).errorDescription?.contains("damaged") == true)
        let withLog = GGUFError.loadFailed(name: "m.gguf", reason: "mmap failed", log: ["a", "b"]).errorDescription
        #expect(withLog == "Could not load m.gguf. llama.cpp said: mmap failed\n\nllama.cpp log:\na\nb")
    }
}
