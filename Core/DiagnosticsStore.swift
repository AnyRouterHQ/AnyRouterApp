import Foundation

/// What a saved MetricKit payload is about.
enum DiagnosticKind: String, Sendable, CaseIterable {
    case crash, hang, cpu, disk, diagnostic, metric
    /// A model list that could not be loaded. Written by the app, not delivered by MetricKit.
    case modelList
    /// The steps of one local model load (`ModelLoadTrace`). Written by the app.
    case modelLoad

    var title: String {
        switch self {
        case .crash: "Crash"
        case .hang: "Hang"
        case .cpu: "CPU exception"
        case .disk: "Disk write exception"
        case .diagnostic: "Diagnostic"
        case .metric: "Metrics"
        case .modelList: "Model list error"
        case .modelLoad: "Model load"
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

/// Exit counts from the newest MetricKit metrics report: how often iOS ended the app, by reason.
struct AppExitCount: Hashable, Sendable {
    /// "Foreground" or "Background".
    var phase: String
    /// "Memory resource limit", "App watchdog", …
    var reason: String
    var count: Int
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

    /// Keeps the reason a model list did not load, so it can be read after a relaunch. Holds the source and the error text only.
    func saveModelListFailure(source: String, message: String, now: Date = Date()) throws {
        let body = try JSONSerialization.data(
            withJSONObject: ["event": "model-list-failed", "source": source, "error": message], options: [.sortedKeys])
        try write(body, kind: .modelList, now: now)
    }

    /// The error text of a model list record, nil for any other kind or a file that does not read.
    func modelListMessage(of record: DiagnosticRecord) -> String? {
        guard record.kind == .modelList, let data = try? Data(contentsOf: record.url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let source = object["source"], let error = object["error"] else { return nil }
        return "\(source): \(error)"
    }

    /// Saves the trace of a load attempt. The first save names its file; pass that name to later saves to replace it, so one
    /// attempt stays one record however many steps it has.
    @discardableResult
    func saveModelLoad(_ trace: ModelLoadTrace, replacing name: String? = nil, now: Date = Date()) throws -> String {
        try write(JSONEncoder().encode(trace), kind: .modelLoad, now: now, name: name)
    }

    /// The trace in a model load record, nil for any other kind or a file that does not read.
    func modelLoadTrace(of record: DiagnosticRecord) -> ModelLoadTrace? {
        guard record.kind == .modelLoad, let data = try? Data(contentsOf: record.url) else { return nil }
        return try? JSONDecoder().decode(ModelLoadTrace.self, from: data)
    }

    /// The non-zero exit counts of the newest metrics report, foreground first. Empty when there is none yet.
    func lastExitCounts() -> [AppExitCount] {
        guard let record = list().first(where: { $0.kind == .metric }), let data = try? Data(contentsOf: record.url) else { return [] }
        return Self.exitCounts(inMetrics: data)
    }

    /// Reads `applicationExitMetrics` of an `MXMetricPayload` JSON. Every `cumulative…ExitCount` key counts, so a reason
    /// a newer iOS adds shows up without a code change.
    static func exitCounts(inMetrics json: Data) -> [AppExitCount] {
        let object = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any]
        let exits = object?["applicationExitMetrics"] as? [String: Any] ?? [:]
        return [("Foreground", "foregroundExitData"), ("Background", "backgroundExitData")].flatMap { phase, key in
            let counts = exits[key] as? [String: Any] ?? [:]
            return counts.keys.sorted().compactMap { name -> AppExitCount? in
                guard name.hasPrefix("cumulative"), name.hasSuffix("ExitCount"),
                      let count = counts[name] as? Int, count > 0 else { return nil }
                let words = name.dropFirst("cumulative".count).dropLast("ExitCount".count)
                return AppExitCount(phase: phase, reason: sentence(fromCamelCase: String(words)), count: count)
            }
        }
    }

    /// "MemoryResourceLimit" to "Memory resource limit"; runs of capitals ("CPU") stay together.
    static func sentence(fromCamelCase text: String) -> String {
        var words: [String] = []
        var current = ""
        let characters = Array(text)
        for (index, character) in characters.enumerated() {
            let next = index + 1 < characters.count ? characters[index + 1] : nil
            let startsWord = character.isUppercase && !current.isEmpty
                && (!(current.last?.isUppercase ?? false) || (next?.isLowercase ?? false))
            if startsWord {
                words.append(current)
                current = ""
            }
            current.append(character)
        }
        if !current.isEmpty { words.append(current) }
        return words.enumerated().map { index, word in
            if index == 0 || word.allSatisfy(\.isUppercase) { return word }
            return word.lowercased()
        }.joined(separator: " ")
    }

    /// Newest first.
    func list() -> [DiagnosticRecord] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.compactMap(Self.record(for:)).sorted { ($0.date, $1.id) > ($1.date, $0.id) }
    }

    @discardableResult
    private func write(_ json: Data, kind: DiagnosticKind, now: Date, name: String? = nil) throws -> String {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let millis = Int(now.timeIntervalSince1970 * 1000)
        let name = name ?? "\(millis)-\(kind.rawValue)-\(UUID().uuidString.prefix(8)).json"
        try json.write(to: directory.appending(path: name), options: .atomic)
        for stale in list().dropFirst(limit) {
            try FileManager.default.removeItem(at: stale.url)
        }
        return name
    }

    private static func record(for url: URL) -> DiagnosticRecord? {
        let parts = url.deletingPathExtension().lastPathComponent.split(separator: "-")
        guard url.pathExtension == "json", parts.count == 3, let millis = Double(parts[0]),
              let kind = DiagnosticKind(rawValue: String(parts[1])) else { return nil }
        return DiagnosticRecord(
            id: url.lastPathComponent, date: Date(timeIntervalSince1970: millis / 1000), kind: kind, url: url)
    }
}
