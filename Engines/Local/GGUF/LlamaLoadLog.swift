import Foundation
import llama
import Synchronization

/// llama.cpp's warnings and errors while a model loads, so a failed load can say why (an mmap error, a missing tensor).
/// Logging is off at every other time: during a chat llama.cpp can echo prompt text.
enum LlamaLoadLog {
    private static let lines = Mutex<[String]>([])

    /// Starts keeping warning and error lines. Call right before `llama_model_load_from_file`.
    static func begin() {
        lines.withLock { $0 = [] }
        llama_log_set({ level, text, _ in
            guard let text, level == GGML_LOG_LEVEL_ERROR || level == GGML_LOG_LEVEL_WARN else { return }
            let line = String(cString: text)
            LlamaLoadLog.lines.withLock { $0.append(line) }
        }, nil)
    }

    /// Turns logging off again and hands back what was kept.
    static func end() -> [String] {
        llama_log_set({ _, _, _ in }, nil)
        return lines.withLock { kept in
            defer { kept = [] }
            return kept
        }
    }

    /// The line that says why a load failed: the last error line, else the last line. File paths are cut to their file
    /// name, so the message names the model, not the app's container. Nil when llama.cpp said nothing.
    static func reason(from lines: [String]) -> String? {
        let kept = lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let failure = kept.last { $0.localizedCaseInsensitiveContains("error") || $0.localizedCaseInsensitiveContains("fail") }
        guard let line = failure ?? kept.last else { return nil }
        let short = line.replacing(#/\/(?:[^\s'"\/]+\/)+([^\s'"\/]+)/#) { String($0.output.1) }
        return String(short.prefix(300))
    }
}
