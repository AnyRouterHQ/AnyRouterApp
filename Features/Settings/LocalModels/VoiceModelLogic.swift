import Foundation

/// A speech model the app can list but not run yet. Speech uses the system voices first (D17); these neural voices
/// need the app to be able to speak with an MLX model, so they stay "Coming soon" instead of a download that does nothing.
struct VoiceModel: Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    /// Hugging Face repo the model would download from.
    var repo: String
    /// "MLX 4-bit".
    var format: String
    var sizeBytes: Int64
    var license: String
    var summary: String

    /// "MLX 4-bit · 89 MB · CC-BY-4.0".
    var detailLine: String {
        [format, FitFormat.gigabytes(sizeBytes), license].joined(separator: " · ")
    }
}

enum VoiceModelCatalog {
    static let status = "Coming soon"

    static let footer = "Spoken replies use the system voices. These models are listed so you can see what is planned; none can be downloaded yet."

    /// Sizes are the repo's files as Hugging Face listed them on 2026-11-27.
    static let all: [VoiceModel] = [
        VoiceModel(
            id: "kokoro", name: "Kokoro", repo: "mlx-community/Kokoro-82M-bf16", format: "MLX bf16", sizeBytes: 389_410_807,
            license: "Apache-2.0", summary: "A small 82M-parameter model with many ready-made voices."),
        VoiceModel(
            id: "soprano", name: "Soprano", repo: "mlx-community/Soprano-1.1-80M-bf16", format: "MLX bf16", sizeBytes: 283_883_377,
            license: "Apache-2.0", summary: "An 80M-parameter model for fast speech."),
        VoiceModel(
            id: "pocket-tts", name: "Pocket TTS", repo: "mlx-community/pocket-tts-4bit", format: "MLX 4-bit", sizeBytes: 89_316_161,
            license: "CC-BY-4.0", summary: "The smallest of the four, built to run on a phone."),
        VoiceModel(
            id: "qwen3-tts", name: "Qwen3 TTS 0.6B", repo: "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit", format: "MLX 8-bit",
            sizeBytes: 1_991_299_138, license: "Apache-2.0", summary: "The largest of the four, with 0.6B parameters."),
    ]
}
