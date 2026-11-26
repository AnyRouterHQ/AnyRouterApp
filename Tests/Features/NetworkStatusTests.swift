import Foundation
import Testing
@testable import AnyRouter

@MainActor
private final class ScriptedPathMonitor: PathMonitoring {
    /// Reported as soon as the monitor starts. Nil reports nothing.
    var firstReport: Bool?

    func start(_ update: @escaping @MainActor @Sendable (Bool) -> Void) {
        if let firstReport { update(firstReport) }
    }

    func stop() {}
}

@MainActor
struct NetworkStatusTests {
    @Test func aWindowlessCallerStartsTheMonitorAndGetsTheFirstReport() async {
        let monitor = ScriptedPathMonitor()
        monitor.firstReport = false
        let status = NetworkStatus(monitor: monitor)
        #expect(!status.hasReported)
        #expect(await status.currentlyOnline() == false)
        #expect(status.hasReported)
    }

    @Test func withoutAReportItAssumesOnlineAfterTheTimeout() async {
        let status = NetworkStatus(monitor: ScriptedPathMonitor())
        #expect(await status.currentlyOnline(timeout: .milliseconds(60)))
        #expect(!status.hasReported)
    }
}
