import Foundation
import Testing
@testable import AnyRouter

/// Records what it is given, so tests can check which events reach the boundary.
final class RecordingTelemetry: Telemetry, @unchecked Sendable {
    private let lock = NSLock()
    private var raw: [TelemetryEvent] = []
    var events: [TelemetryEvent] { lock.withLock { raw } }
    func track(_ event: TelemetryEvent) { lock.withLock { raw.append(event) } }
}

private struct OddError: Error, CustomStringConvertible {
    var description: String { "free text with spaces (secret)" }
}

struct TelemetryEventTests {
    @Test func everyEventHasASnakeCaseNameAndStringProperties() {
        let all: [(TelemetryEvent, String, TelemetryCategory, [String: String])] = [
            (.appOpen, "app_open", .app, [:]),
            (.signInOK, "sign_in_ok", .auth, [:]),
            (.signInFail(reason: "Cancelled"), "sign_in_fail", .auth, ["reason": "cancelled"]),
            (.modelSelected(source: .gguf), "model_selected", .chat, ["source": "gguf"]),
            (.messageSent(source: .apple), "message_sent", .chat, ["source": "apple"]),
            (.firstTokenMs(420, source: .anyrouter), "first_token_ms", .chat, ["ms": "420", "source": "anyrouter"]),
            (.downloadOK, "download_ok", .download, [:]),
            (.downloadFail(reason: "http"), "download_fail", .download, ["reason": "http"]),
            (.engineLoadMs(1500, source: .mlx), "engine_load_ms", .engine, ["ms": "1500", "source": "mlx"]),
            (.crashSeen(kind: "hang"), "crash_seen", .app, ["kind": "hang"]),
        ]
        for (event, name, category, properties) in all {
            #expect(event.name == name)
            #expect(event.category == category)
            #expect(event.properties == properties)
        }
    }

    @Test func logLineIsSortedKeyValuePairs() {
        #expect(TelemetryEvent.firstTokenMs(7, source: .gguf).logLine == "ms=7 source=gguf")
        #expect(TelemetryEvent.appOpen.logLine == "")
    }

    @Test func freeTextCannotPassAsACode() {
        #expect(TelemetryEvent.code("Could not sign in: bob@example.com") == "could_not_sign_in__bob_example_com")
        #expect(TelemetryEvent.code(String(repeating: "a", count: 90)).count == 40)
        #expect(TelemetryEvent.code("") == "unknown")
        #expect(TelemetryEvent.code("\u{00E9}") == "_")
    }

    @Test func errorsBecomeCodesWithoutTheirMessage() {
        #expect(TelemetryEvent.reasonCode(for: LocalModelError.http(status: 404)) == "http")
        #expect(TelemetryEvent.reasonCode(for: LocalModelError.sizeMismatch("secret/path.gguf")) == "sizemismatch")
        #expect(TelemetryEvent.reasonCode(for: TestFailure(message: "boom")) == "testfailure")
        #expect(TelemetryEvent.reasonCode(for: OddError()) == "odderror", "a message with spaces falls back to the type name")
    }

    @Test func durationsBecomeWholeMilliseconds() {
        #expect(TelemetryEvent.milliseconds(.milliseconds(1250)) == 1250)
        #expect(TelemetryEvent.milliseconds(.seconds(3)) == 3000)
    }
}

struct TelemetryBoundaryTests {
    private final class CapturingSink: TelemetrySink, @unchecked Sendable {
        private let lock = NSLock()
        private var raw: [TelemetryEvent] = []
        var events: [TelemetryEvent] { lock.withLock { raw } }
        func record(_ event: TelemetryEvent) { lock.withLock { raw.append(event) } }
    }

    @Test func noopTelemetryDoesNothing() {
        NoopTelemetry().track(.appOpen)
    }

    @Test func loggingTelemetryForwardsToTheSinkWhileSharingIsOn() {
        let sink = CapturingSink()
        let telemetry = LoggingTelemetry(sink: sink)
        telemetry.track(.appOpen)
        telemetry.track(.signInFail(reason: "x"))
        #expect(sink.events == [.appOpen, .signInFail(reason: "x")])
    }

    @Test func optingOutStopsEveryForward() {
        let sink = CapturingSink()
        let telemetry = LoggingTelemetry(sink: sink, shareEnabled: { false })
        telemetry.track(.appOpen)
        #expect(sink.events.isEmpty)
    }

    @Test func withoutASinkTrackingStillLogsLocally() {
        LoggingTelemetry(sink: nil).track(.downloadOK)
    }

    @Test func everyCategoryHasALoggerName() {
        #expect(TelemetryCategory.allCases.map(\.rawValue) == ["app", "auth", "chat", "engine", "download", "mcp"])
    }
}

struct DiagnosticsConfigTests {
    private final class CountingSink: TelemetrySink, @unchecked Sendable {
        func record(_ event: TelemetryEvent) {}
    }

    @Test func emptyOrBrokenDSNMeansOff() {
        for raw in [nil, "", "   ", "$(SENTRY_DSN)", "not a url", "http://key@host/1", "https://"] as [String?] {
            #expect(DiagnosticsConfig.dsn(from: raw) == nil, "\(raw ?? "nil")")
            #expect(DiagnosticsConfig.defaultShare(dsn: raw) == false)
        }
    }

    @Test func httpsDSNIsKeptAndTrimmed() {
        let dsn = "https://abc123@o1.ingest.example.io/42"
        #expect(DiagnosticsConfig.dsn(from: "  \(dsn)\n") == dsn)
        #expect(DiagnosticsConfig.defaultShare(dsn: dsn))
    }

    @Test func emptyDSNNeverBuildsASink() {
        var built = 0
        let telemetry = DiagnosticsConfig.makeTelemetry(dsn: "", shareEnabled: { true }, makeSink: { _ in
            built += 1
            return CountingSink()
        })
        telemetry.track(.appOpen)
        #expect(built == 0, "no DSN, so no vendor SDK and no network")
        #expect((telemetry as? LoggingTelemetry)?.sink == nil)
    }

    @Test func aDSNBuildsTheSinkOnce() {
        var received: [String] = []
        let telemetry = DiagnosticsConfig.makeTelemetry(
            dsn: "https://k@h.example.io/1", shareEnabled: { true }, makeSink: { dsn in
                received.append(dsn)
                return CountingSink()
            })
        #expect(received == ["https://k@h.example.io/1"])
        #expect((telemetry as? LoggingTelemetry)?.sink != nil)
    }
}
