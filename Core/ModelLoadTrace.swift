import Foundation

/// One attempt to load a local model and answer with it, saved at every step. When the system ends the app (out of memory,
/// say) there is no callback, so the steps already saved are the evidence of how far it got. Settings › Diagnostics lists it.
struct ModelLoadTrace: Codable, Equatable, Sendable {
    enum Step: String, Codable, Sendable {
        case started
        /// The weights are mapped and the model is ready; the note says how it runs (GPU layers or streamed, context).
        case mapped
        case contextReady
        case firstToken
        case finished
        case stopped
        case failed

        var title: String {
            switch self {
            case .started: "started"
            case .mapped: "mapped"
            case .contextReady: "context ready"
            case .firstToken: "first token"
            case .finished: "finished"
            case .stopped: "stopped"
            case .failed: "failed"
            }
        }
    }

    struct Stage: Codable, Equatable, Sendable {
        var step: Step
        /// Since the attempt started.
        var seconds: Double
        /// What the system charged the app, and what it had left, at this step.
        var footprintBytes: Int64
        var availableBytes: Int64
        var note: String?
    }

    /// The model file name. Never a repo or a path.
    var model: String
    var stages: [Stage] = []

    /// One paragraph for the Diagnostics list: each step with its time and note, the memory at the last one, and a
    /// warning when the attempt ended with no last step (the system ended the app, or it was closed).
    var summary: String {
        let steps = stages.map { stage in
            "\(stage.step.title) \(String(format: "%.1f", stage.seconds)) s" + (stage.note.map { " (\($0))" } ?? "")
        }
        var text = ([model] + steps).joined(separator: " · ")
        if let last = stages.last {
            text += ". App memory \(Self.gigabytes(last.footprintBytes)), \(Self.gigabytes(last.availableBytes)) left."
            if ![.finished, .stopped, .failed].contains(last.step) {
                text += " Ended after \(last.step.title): the system may have closed the app."
            }
        }
        return text
    }

    private static func gigabytes(_ bytes: Int64) -> String {
        String(format: "%.2f GB", Double(bytes) / 1_000_000_000)
    }
}
