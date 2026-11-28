import Foundation
import Network

/// `NWPathMonitor` behind `PathMonitoring`. Only a satisfied path counts as online. The system delivers updates on its
/// own queue, so each one hops to the main actor.
@MainActor
final class SystemPathMonitor: PathMonitoring {
    private var monitor: NWPathMonitor?

    func start(_ update: @escaping @MainActor @Sendable (Bool) -> Void) {
        stop()
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { path in
            let online = path.status == .satisfied
            Task { @MainActor in update(online) }
        }
        monitor.start(queue: DispatchQueue(label: "oneni.anyr.app.network"))
        self.monitor = monitor
    }

    func stop() {
        monitor?.cancel()
        monitor = nil
    }
}
