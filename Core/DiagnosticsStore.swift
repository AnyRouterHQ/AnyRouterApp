import Foundation

/// What a saved MetricKit payload is about.
enum DiagnosticKind: String, Sendable, CaseIterable {
    case crash, hang, cpu, disk, diagnostic, metric

    var title: String {
        switch self {
        case .crash: "Crash"
        case .hang: "Hang"
        case .cpu: "CPU exception"
        case .disk: "Disk write exception"
        case .diagnostic: "Diagnostic"
        case .metric: "Metrics"
        }
    }

    /// Reads which diagnostics an `MXDiagnosticPayload` JSON holds. Crash wins over hang, then CPU, then disk.
    static func classify(diagnostics json: Data) -> DiagnosticKind {
        let object = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any]
        let keys: [(String, DiagnosticKind)] = [
            ("crashDiagnostics", .crash), ("hangDiagnostics", .hang),
            ("cpuExceptionDiagnostics", .cpu), ("diskWriteExceptionDiagnostics", .disk),
        ]
        let found = keys.first { key, _ in !((object?[key] as? [Any])?.isEmpty ?? true) }
        return found?.1 ?? .diagnostic
    }
}

struct DiagnosticRecord: Identifiable, Equatable, Sendable {
    let id: String
    let date: Date
    let kind: DiagnosticKind
    let url: URL
}

/// MetricKit payloads kept as JSON files in Application Support. Only the newest `limit` stay.
/// File name: `<unix ms>-<kind>-<8 hex>.json`, so listing needs no index.
struct DiagnosticsStore: Sendable {
    static let defaultLimit = 20

    let directory: URL
    let limit: Int

    init(
        directory: URL = URL.applicationSupportDirectory.appending(path: "Diagnostics", directoryHint: .isDirectory),
        limit: Int = DiagnosticsStore.defaultLimit
    ) {
        self.directory = directory
        self.limit = limit
    }

    @discardableResult
    func saveDiagnostics(_ json: Data, now: Date = Date()) throws -> DiagnosticKind {
        let kind = DiagnosticKind.classify(diagnostics: json)
        try write(json, kind: kind, now: now)
        return kind
    }

    func saveMetrics(_ json: Data, now: Date = Date()) throws {
        try write(json, kind: .metric, now: now)
    }

    /// Newest first.
    func list() -> [DiagnosticRecord] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.compactMap(Self.record(for:)).sorted { ($0.date, $1.id) > ($1.date, $0.id) }
    }

    private func write(_ json: Data, kind: DiagnosticKind, now: Date) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let millis = Int(now.timeIntervalSince1970 * 1000)
        let name = "\(millis)-\(kind.rawValue)-\(UUID().uuidString.prefix(8)).json"
        try json.write(to: directory.appending(path: name), options: .atomic)
        for stale in list().dropFirst(limit) {
            try FileManager.default.removeItem(at: stale.url)
        }
    }

    private static func record(for url: URL) -> DiagnosticRecord? {
        let parts = url.deletingPathExtension().lastPathComponent.split(separator: "-")
        guard url.pathExtension == "json", parts.count == 3, let millis = Double(parts[0]),
              let kind = DiagnosticKind(rawValue: String(parts[1])) else { return nil }
        return DiagnosticRecord(
            id: url.lastPathComponent, date: Date(timeIntervalSince1970: millis / 1000), kind: kind, url: url)
    }
}
