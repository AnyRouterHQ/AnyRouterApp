import Foundation
import os

/// Where an event belongs. These are the `os.Logger` categories.
enum TelemetryCategory: String, CaseIterable, Sendable {
    case app, auth, chat, engine, download, mcp
}

/// The fixed set of things the app reports. Every value is a number, a model source or a short code,
/// so no case can carry a prompt, a key, an email or any free-form text.
enum TelemetryEvent: Sendable, Equatable {
    case appOpen
    case signInOK
    case signInFail(reason: String)
    case modelSelected(source: ModelSource)
    case messageSent(source: ModelSource)
    case firstTokenMs(Int, source: ModelSource)
    case downloadOK
    case downloadFail(reason: String)
    case engineLoadMs(Int, source: ModelSource)
    case crashSeen(kind: String)

    var name: String {
        switch self {
        case .appOpen: "app_open"
        case .signInOK: "sign_in_ok"
        case .signInFail: "sign_in_fail"
        case .modelSelected: "model_selected"
        case .messageSent: "message_sent"
        case .firstTokenMs: "first_token_ms"
        case .downloadOK: "download_ok"
        case .downloadFail: "download_fail"
        case .engineLoadMs: "engine_load_ms"
        case .crashSeen: "crash_seen"
        }
    }

    var category: TelemetryCategory {
        switch self {
        case .appOpen, .crashSeen: .app
        case .signInOK, .signInFail: .auth
        case .modelSelected, .messageSent, .firstTokenMs: .chat
        case .downloadOK, .downloadFail: .download
        case .engineLoadMs: .engine
        }
    }

    /// String key/value pairs sent with the event. Reason codes are cleaned by `code(_:)`.
    var properties: [String: String] {
        switch self {
        case .appOpen, .signInOK, .downloadOK: [:]
        case .signInFail(let reason), .downloadFail(let reason): ["reason": Self.code(reason)]
        case .modelSelected(let source), .messageSent(let source): ["source": source.rawValue]
        case .firstTokenMs(let ms, let source), .engineLoadMs(let ms, let source):
            ["ms": String(ms), "source": source.rawValue]
        case .crashSeen(let kind): ["kind": Self.code(kind)]
        }
    }

    /// `key=value` pairs in a fixed order, for the log line.
    var logLine: String {
        properties.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
    }

    /// Lowercase `[a-z0-9_]`, at most 40 characters, never empty. Free text cannot get through as a code.
    static func code(_ raw: String) -> String {
        let mapped = raw.lowercased().unicodeScalars.map { scalar in
            scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || scalar == "_") ? Character(scalar) : "_"
        }
        let text = String(mapped.prefix(40))
        return text.isEmpty ? "unknown" : text
    }

    /// A code for an error that never includes its message: the enum case name, else the type name.
    static func reasonCode(for error: Error) -> String {
        let text = String(describing: error)
        let name = text.prefix { $0 != "(" }
        let isCaseName = !name.isEmpty && name.allSatisfy { $0.isLetter || $0.isNumber }
        return code(isCaseName ? String(name) : String(describing: type(of: error)))
    }

    static func milliseconds(_ duration: Duration) -> Int {
        let parts = duration.components
        return Int(parts.seconds * 1000 + parts.attoseconds / 1_000_000_000_000_000)
    }
}

/// The one door the app uses to report events. Views and engines never see a vendor SDK.
protocol Telemetry: Sendable {
    func track(_ event: TelemetryEvent)
}

struct NoopTelemetry: Telemetry {
    func track(_ event: TelemetryEvent) {}
}

/// The vendor side of the boundary. The app target supplies one (Sentry) only when a DSN is set.
protocol TelemetrySink: Sendable {
    func record(_ event: TelemetryEvent)
}

/// Logs every event with `os.Logger` (on the device only) and forwards it to the sink while sharing is on.
struct LoggingTelemetry: Telemetry {
    static let subsystem = "dev.anyrouter.app"

    let sink: (any TelemetrySink)?
    let shareEnabled: @Sendable () -> Bool

    init(sink: (any TelemetrySink)?, shareEnabled: @escaping @Sendable () -> Bool = { true }) {
        self.sink = sink
        self.shareEnabled = shareEnabled
    }

    func track(_ event: TelemetryEvent) {
        Logger(subsystem: Self.subsystem, category: event.category.rawValue)
            .info("\(event.name, privacy: .public) \(event.logLine, privacy: .public)")
        guard let sink, shareEnabled() else { return }
        sink.record(event)
    }
}

enum DiagnosticsConfig {
    /// A usable DSN, or nil. nil means remote reporting is off: no SDK start and no network.
    static func dsn(from raw: String?) -> String? {
        let text = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let url = URL(string: text), url.scheme == "https", url.host() != nil else { return nil }
        return text
    }

    /// Sharing is on by default only when a DSN exists.
    static func defaultShare(dsn raw: String?) -> Bool { dsn(from: raw) != nil }

    /// Builds the telemetry the app uses. `makeSink` runs only for a usable DSN.
    static func makeTelemetry(
        dsn raw: String?, shareEnabled: @escaping @Sendable () -> Bool,
        makeSink: (String) -> any TelemetrySink
    ) -> any Telemetry {
        LoggingTelemetry(sink: dsn(from: raw).map(makeSink), shareEnabled: shareEnabled)
    }
}
