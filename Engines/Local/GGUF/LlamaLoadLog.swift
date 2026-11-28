import Foundation
import llama
import Synchronization

/// llama.cpp's warnings and errors while a model loads, so a failed load can say why (an mmap error, a missing tensor).
/// Logging is off at every other time: during a chat llama.cpp can echo prompt text.
enum LlamaLoadLog {
    /// One warning or error line as llama.cpp printed it.
    struct Line: Equatable, Sendable {
        let isError: Bool
        let text: String
    }

    /// Lines kept for the reply's details and the Diagnostics load record.
    static let trailLength = 20

    private static let lines = Mutex<[Line]>([])

    /// Starts keeping warning and error lines. Call right before `llama_model_load_from_file`.
    static func begin() {
        lines.withLock { $0 = [] }
        llama_log_set({ level, text, _ in
            guard let text, level == GGML_LOG_LEVEL_ERROR || level == GGML_LOG_LEVEL_WARN else { return }
            let line = Line(isError: level == GGML_LOG_LEVEL_ERROR, text: String(cString: text))
            LlamaLoadLog.lines.withLock { $0.append(line) }
        }, nil)
    }

    /// Turns logging off again and hands back what was kept.
    static func end() -> [Line] {
        llama_log_set({ _, _, _ in }, nil)
        return lines.withLock { kept in
            defer { kept = [] }
            return kept
        }
    }

    /// The line that says why a load failed. llama.cpp always ends a failed load with the generic
    /// "llama_model_load_from_file_impl: failed to load model", so that line is never the answer while a more specific
    /// one exists: first "error loading model: <cause>", else the first error line that is not the summary, else the
    /// last line. File paths are cut to their file name. Nil when llama.cpp said nothing.
    static func reason(from lines: [Line]) -> String? {
        let kept = cleaned(lines)
        let cause = kept.first { $0.text.localizedCaseInsensitiveContains("error loading model") }
            ?? kept.first { $0.isError && !isSummary($0.text) }
            ?? kept.last
        return cause.map { short($0.text) }
    }

    /// The last few warning and error lines, paths cut to file names, for the reply's details and Diagnostics.
    static func trail(from lines: [Line]) -> [String] {
        cleaned(lines).suffix(trailLength).map { short($0.text) }
    }

    private static func cleaned(_ lines: [Line]) -> [Line] {
        lines.map { Line(isError: $0.isError, text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines)) }.filter { !$0.text.isEmpty }
    }

    private static func isSummary(_ text: String) -> Bool {
        text.localizedCaseInsensitiveContains("failed to load model")
    }

    private static func short(_ text: String) -> String {
        String(text.replacing(#/\/(?:[^\s'"\/]+\/)+([^\s'"\/]+)/#) { String($0.output.1) }.prefix(300))
    }
}
