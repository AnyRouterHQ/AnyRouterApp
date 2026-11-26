import Foundation

/// App-side wiring of diagnostics. The pure logic lives in Core/ (`DiagnosticsConfig`, `DiagnosticsStore`).
enum Diagnostics {
    /// Sentry starts this long after launch, so it never competes with the first frame.
    static let sentryStartDelay: Duration = .milliseconds(500)

    /// `SentryDSN` in Info.plist, filled from the `SENTRY_DSN` build setting. Empty or invalid means off.
    static var infoPlistDSN: String? { Bundle.main.object(forInfoDictionaryKey: "SentryDSN") as? String }

    static var dsn: String? { DiagnosticsConfig.dsn(from: infoPlistDSN) }

    static var isConfigured: Bool { dsn != nil }

    /// Logs always; forwards to Sentry only with a DSN and while "Share anonymous diagnostics" is on.
    /// The Sentry SDK starts on a utility task after `sentryStartDelay`, never inside the caller, and only when sharing
    /// is on. Turning sharing on takes effect at the next launch.
    static func makeTelemetry(
        dsn raw: String? = Diagnostics.infoPlistDSN,
        shares: @escaping @Sendable () -> Bool = { AppSettings.sharesDiagnostics() },
        startSDK: @escaping @Sendable (String, @escaping @Sendable () -> Bool) -> Void = SentryTelemetrySink.start
    ) -> any Telemetry {
        DiagnosticsConfig.makeTelemetry(dsn: raw, shareEnabled: shares, makeSink: { dsn in
            if shares() {
                Task.detached(priority: .utility) {
                    try? await Task.sleep(for: sentryStartDelay)
                    let signpost = Perf.signposter.beginInterval("launch.sentry")
                    startSDK(dsn, shares)
                    Perf.signposter.endInterval("launch.sentry", signpost)
                }
            }
            return SentryTelemetrySink()
        })
    }
}
