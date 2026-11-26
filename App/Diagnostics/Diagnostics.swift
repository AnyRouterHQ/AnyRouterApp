import Foundation

/// App-side wiring of diagnostics. The pure logic lives in Core/ (`DiagnosticsConfig`, `DiagnosticsStore`).
enum Diagnostics {
    /// `SentryDSN` in Info.plist, filled from the `SENTRY_DSN` build setting. Empty or invalid means off.
    static var dsn: String? {
        DiagnosticsConfig.dsn(from: Bundle.main.object(forInfoDictionaryKey: "SentryDSN") as? String)
    }

    static var isConfigured: Bool { dsn != nil }

    /// Logs always; forwards to Sentry only with a DSN and while "Share anonymous diagnostics" is on.
    /// The Sentry SDK itself starts at launch only when sharing is on, so turning it on takes effect at the next launch.
    static func makeTelemetry() -> any Telemetry {
        DiagnosticsConfig.makeTelemetry(
            dsn: Bundle.main.object(forInfoDictionaryKey: "SentryDSN") as? String,
            shareEnabled: { AppSettings.sharesDiagnostics() },
            makeSink: { dsn in
                if AppSettings.sharesDiagnostics() {
                    SentryTelemetrySink.start(dsn: dsn, shareEnabled: { AppSettings.sharesDiagnostics() })
                }
                return SentryTelemetrySink()
            })
    }
}
