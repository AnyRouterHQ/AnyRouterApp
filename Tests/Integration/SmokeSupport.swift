import Foundation

/// Real-model smoke tests only run in `model-smoke.yml`, which sets these (as `TEST_RUNNER_*` on xcodebuild).
enum SmokeEnv {
    private static let env = ProcessInfo.processInfo.environment

    /// `1` when the smoke job runs. Gates tests that need the network or the real Apple model.
    static var enabled: Bool { env["ANYROUTER_SMOKE"] == "1" }
    /// The cached GGUF file the workflow downloaded.
    static var ggufPath: String? { env["ANYROUTER_SMOKE_GGUF_PATH"] }
    /// Expected sha256 of that file, from the Hugging Face listing.
    static var ggufSHA256: String? { env["ANYROUTER_SMOKE_GGUF_SHA256"] }
    /// Catalog id (`gguf/<repo>/<file>`) of the downloaded file. Unset means the smallest GGUF in the catalog.
    static var ggufModelID: String? { env["ANYROUTER_SMOKE_MODEL_ID"].flatMap { $0.isEmpty ? nil : $0 } }
    /// `1` when the GGUF is not a catalog model (a Hugging Face repo and file given to the workflow at run time).
    /// Then reports must not name the model.
    static var external: Bool { env["ANYROUTER_SMOKE_EXTERNAL"] == "1" }
    /// The catalog entry to run, as JSON, resolved by the workflow from models.json, dev-models.json or its inputs.
    static var entryJSON: String? { env["ANYROUTER_SMOKE_ENTRY_JSON"].flatMap { $0.isEmpty ? nil : $0 } }
    /// Folder with the Gemma 4 MLX tokenizer files (no weights), for the chat template check.
    static var mlxTokenizerDir: String? { env["ANYROUTER_SMOKE_MLX_TOKENIZER_DIR"] }
}

/// Collects findings as Markdown table rows for the job summary. Does nothing when `ANYROUTER_SMOKE_REPORT` is unset.
enum SmokeReport {
    static func record(_ key: String, _ value: String) {
        guard let path = ProcessInfo.processInfo.environment["ANYROUTER_SMOKE_REPORT"] else { return }
        let clean = value.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "|", with: "\\|")
        let row = Data("| \(key) | \(clean) |\n".utf8)
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil)
        }
        guard let handle = FileHandle(forWritingAtPath: path) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: row)
    }
}
