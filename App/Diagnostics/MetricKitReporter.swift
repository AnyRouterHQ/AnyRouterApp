import MetricKit

/// Saves the crash, hang and metric payloads the system delivers (usually the day after) into `DiagnosticsStore`.
final class MetricKitReporter: NSObject, MXMetricManagerSubscriber {
    private let store: DiagnosticsStore
    private let telemetry: any Telemetry

    init(store: DiagnosticsStore, telemetry: any Telemetry) {
        self.store = store
        self.telemetry = telemetry
    }

    func start() {
        MXMetricManager.shared.add(self)
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads { try? store.saveMetrics(payload.jsonRepresentation()) }
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            guard let kind = try? store.saveDiagnostics(payload.jsonRepresentation()) else { continue }
            telemetry.track(.crashSeen(kind: kind.rawValue))
        }
    }
}
