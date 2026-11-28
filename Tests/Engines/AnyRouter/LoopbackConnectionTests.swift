import Foundation
import Network
import Testing
@testable import AnyRouter

@MainActor
struct LoopbackConnectionTests {
    private func waitUntil(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<100 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return condition()
    }

    private func connect(to port: UInt16) -> NWConnection {
        let connection = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
        connection.start(queue: .main)
        return connection
    }

    @Test func idleConnectionIsClosedAfterTheTimeout() async throws {
        let loopback = LoopbackCallback(expectedState: "s", connectionTimeout: .milliseconds(300))
        let port = try await loopback.start()
        defer { loopback.stop() }
        let client = connect(to: port)
        defer { client.cancel() }
        #expect(await waitUntil { loopback.openConnectionCount == 1 })
        #expect(await waitUntil { loopback.openConnectionCount == 0 })
    }

    @Test func stopClosesOpenConnections() async throws {
        let loopback = LoopbackCallback(expectedState: "s")
        let port = try await loopback.start()
        let client = connect(to: port)
        defer { client.cancel() }
        #expect(await waitUntil { loopback.openConnectionCount == 1 })
        loopback.stop()
        #expect(loopback.openConnectionCount == 0)
    }
}
