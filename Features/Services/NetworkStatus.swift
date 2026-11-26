import Foundation
import Observation

/// Reports whether the device has a usable connection. `SystemPathMonitor` is the real one; tests pass a fake.
@MainActor
protocol PathMonitoring {
    /// Calls `update` with the current state and again on every change. `true` means a usable path.
    func start(_ update: @escaping @MainActor @Sendable (Bool) -> Void)
    func stop()
}

/// Whether the device is online, for the model picker, the tools and the chat. It assumes online until the monitor says
/// otherwise, so a slow first report never blocks a send.
@MainActor @Observable
final class NetworkStatus {
    private(set) var isOnline = true
    @ObservationIgnored private let monitor: any PathMonitoring
    @ObservationIgnored private var isRunning = false

    init(monitor: any PathMonitoring = SystemPathMonitor()) {
        self.monitor = monitor
    }

    var isOffline: Bool { !isOnline }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        monitor.start { [weak self] online in self?.isOnline = online }
    }

    func stop() {
        monitor.stop()
        isRunning = false
    }
}
