import Foundation

/// Where one model stands. UI reads it; `ModelDownloadManager` drives it through `reduce`.
enum ModelDownloadState: Equatable, Sendable {
    case notInstalled
    case downloading(received: Int64, total: Int64)
    case paused(received: Int64, total: Int64)
    case verifying
    case installed
    case failed(String)

    /// This change ends a download: the model is installed now and was not before.
    func finishes(into next: ModelDownloadState) -> Bool { next == .installed && self != .installed }

    /// 0...1 while downloading or paused with a known total.
    var fraction: Double? {
        switch self {
        case .downloading(let received, let total), .paused(let received, let total):
            total > 0 ? min(1, Double(received) / Double(total)) : nil
        default: nil
        }
    }

    var isActive: Bool {
        switch self {
        case .downloading, .paused, .verifying: true
        default: false
        }
    }
}

enum ModelDownloadEvent: Equatable, Sendable {
    case start(total: Int64)
    case progress(received: Int64, total: Int64)
    case pause
    case resume
    case downloaded
    case verified
    case fail(String)
    case cancel
    case delete
}

extension ModelDownloadState {
    /// Pure transition function. An event that makes no sense in the current state is ignored,
    /// so a late progress callback after a pause or cancel cannot revive a download.
    func reduce(_ event: ModelDownloadEvent) -> ModelDownloadState {
        switch (self, event) {
        case (.notInstalled, .start(let total)), (.failed, .start(let total)):
            return .downloading(received: 0, total: total)
        case (.downloading, .progress(let received, let total)):
            return .downloading(received: max(0, received), total: total)
        case (.downloading(let received, let total), .pause):
            return .paused(received: received, total: total)
        case (.paused(let received, let total), .resume):
            return .downloading(received: received, total: total)
        case (.downloading, .downloaded):
            return .verifying
        case (.verifying, .verified):
            return .installed
        case (.downloading, .fail(let message)), (.paused, .fail(let message)), (.verifying, .fail(let message)):
            return .failed(message)
        case (.downloading, .cancel), (.paused, .cancel), (.verifying, .cancel):
            return .notInstalled
        case (.installed, .delete), (.failed, .delete):
            return .notInstalled
        default:
            return self
        }
    }
}

/// Adds up per-file byte counts into one number for a multi-file model.
struct DownloadProgressTracker: Sendable {
    private(set) var expected: [String: Int64]
    private var received: [String: Int64] = [:]
    private var finished: Set<String> = []

    init(files: [HFFile]) {
        expected = Dictionary(files.map { ($0.path, $0.size) }, uniquingKeysWith: { first, _ in first })
    }

    var totalBytes: Int64 { expected.values.reduce(0, +) }

    var receivedBytes: Int64 {
        expected.reduce(Int64(0)) { sum, item in
            sum + (finished.contains(item.key) ? item.value : min(received[item.key] ?? 0, item.value))
        }
    }

    var isComplete: Bool { finished.count == expected.count }

    var remainingPaths: [String] { expected.keys.filter { !finished.contains($0) }.sorted() }

    mutating func update(path: String, receivedBytes: Int64) {
        guard expected[path] != nil, !finished.contains(path) else { return }
        received[path] = max(received[path] ?? 0, receivedBytes)
    }

    mutating func markFinished(path: String) {
        guard expected[path] != nil else { return }
        finished.insert(path)
    }

    mutating func reset(path: String) {
        finished.remove(path)
        received[path] = 0
    }
}
