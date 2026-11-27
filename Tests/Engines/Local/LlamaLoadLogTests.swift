import Testing
@testable import AnyRouter

/// A load that fails on the phone must say why on screen: the mmap error, not "the file may be damaged".
struct LlamaLoadLogTests {
    @Test func theLastErrorLineIsTheReasonWithThePathCutToTheFileName() {
        let lines = [
            "llama_model_loader: loaded meta data with 40 key-value pairs\n",
            "warning: failed to mlock 1024-byte buffer\n",
            "llama_model_load: error loading model: mmap failed: Cannot allocate memory (/var/mobile/Containers/Data/Application/ABC/Library/Models/x/Inkling-2-Mini-AD-IQ1_S.gguf)\n",
            "llama_model_load_from_file_impl: failed to load model\n",
        ]
        #expect(LlamaLoadLog.reason(from: lines) == "llama_model_load_from_file_impl: failed to load model")
        let mmap = LlamaLoadLog.reason(from: Array(lines.prefix(3)))
        #expect(mmap == "llama_model_load: error loading model: mmap failed: Cannot allocate memory (Inkling-2-Mini-AD-IQ1_S.gguf)")
    }

    @Test func withoutAnErrorLineTheLastLineIsKeptAndSilenceGivesNoReason() {
        #expect(LlamaLoadLog.reason(from: ["tensor 'x' has 6/8 rows\n", "  \n"]) == "tensor 'x' has 6/8 rows")
        #expect(LlamaLoadLog.reason(from: []) == nil)
        #expect(LlamaLoadLog.reason(from: ["\n", " "]) == nil)
    }

    @Test func aLongLineIsCut() {
        #expect(LlamaLoadLog.reason(from: [String(repeating: "e", count: 1000)])?.count == 300)
    }

    @Test func theMessageQuotesLlamaWhenItSaidSomething() {
        #expect(GGUFError.loadFailed(name: "m.gguf", reason: "mmap failed").errorDescription
            == "Could not load m.gguf. llama.cpp said: mmap failed")
        #expect(GGUFError.loadFailed(name: "m.gguf", reason: nil).errorDescription?.contains("damaged") == true)
    }
}
