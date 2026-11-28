import Foundation
import Network

/// Accepts the OAuth redirect on `127.0.0.1`. The code is useless without the PKCE
/// verifier, which never leaves this process. Only a request carrying the expected
/// `state` and a `code` is delivered: every app on the phone shares the loopback
/// interface, so the first hit is not trusted.
@MainActor
final class LoopbackCallback {
    var onURL: ((URL) -> Void)?
    private(set) var delivered = false
    private let expectedState: String
    private var listener: NWListener?
    private var port: UInt16 = 0
    private let connectionTimeout: Duration
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    var openConnectionCount: Int { connections.count }

    init(expectedState: String, connectionTimeout: Duration = .seconds(10)) {
        self.expectedState = expectedState
        self.connectionTimeout = connectionTimeout
    }

    func start() async throws -> UInt16 {
        let listener: NWListener
        do {
            // Loopback only: the phone stays an outbound client and opens no LAN port.
            let parameters = NWParameters.tcp
            parameters.requiredInterfaceType = .loopback
            listener = try NWListener(using: parameters, on: .any)
        } catch {
            throw OAuthClient.Failure.message("Could not open the sign-in callback.")
        }
        self.listener = listener
        // All Network callbacks run on the main queue, so they are main-actor isolated.
        listener.newConnectionHandler = { [weak self] connection in
            MainActor.assumeIsolated { self?.accept(connection) }
        }
        return try await withCheckedThrowingContinuation { continuation in
            let once = Once()
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    let ready = listener.port?.rawValue ?? 0
                    MainActor.assumeIsolated { self?.port = ready }
                    once.run {
                        if ready == 0 {
                            continuation.resume(throwing: OAuthClient.Failure.message("Could not open the sign-in callback."))
                        } else {
                            continuation.resume(returning: ready)
                        }
                    }
                case .failed:
                    once.run {
                        continuation.resume(throwing: OAuthClient.Failure.message("Could not open the sign-in callback."))
                    }
                default:
                    break
                }
            }
            listener.start(queue: .main)
            Task {
                try? await Task.sleep(for: .seconds(5))
                once.run {
                    listener.cancel()
                    continuation.resume(throwing: OAuthClient.Failure.message("Could not open the sign-in callback."))
                }
            }
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        for connection in connections.values { connection.cancel() }
        connections.removeAll()
    }

    private func accept(_ connection: NWConnection) {
        // A connection that arrives after stop() is never tracked, so close it at once.
        guard listener != nil else {
            connection.cancel()
            return
        }
        let id = ObjectIdentifier(connection)
        connections[id] = connection
        connection.stateUpdateHandler = { [weak self] state in
            if case .cancelled = state {
                MainActor.assumeIsolated { _ = self?.connections.removeValue(forKey: id) }
            }
        }
        connection.start(queue: .main)
        receive(connection, buffer: Data())
        // Any app on the phone can open this port and send nothing.
        let timeout = connectionTimeout
        Task { [weak self] in
            try? await Task.sleep(for: timeout)
            self?.connections[id]?.cancel()
        }
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, isComplete, error in
            MainActor.assumeIsolated {
                guard let self else {
                    connection.cancel()
                    return
                }
                var next = buffer
                if let data { next.append(data) }
                if let range = next.range(of: Data([13, 10, 13, 10])) {
                    self.finishHTTP(next.subdata(in: next.startIndex..<range.lowerBound), connection)
                    return
                }
                if isComplete || error != nil || next.count > 64 * 1024 {
                    connection.cancel()
                    return
                }
                self.receive(connection, buffer: next)
            }
        }
    }

    private func finishHTTP(_ head: Data, _ connection: NWConnection) {
        guard let text = String(data: head, encoding: .utf8),
            let line = text.split(separator: "\r\n", maxSplits: 1).first
        else {
            reply(connection, "400 Bad Request", "Bad request")
            return
        }
        let parts = line.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET",
            let url = Self.callbackURL(String(parts[1]), port: port), Self.hasCodeAndState(url, state: expectedState)
        else {
            reply(connection, "404 Not Found", "Not found")
            return
        }
        reply(connection, "200 OK", "<!doctype html><title>Signed in</title><p>You can return to AnyRouter.</p>") {
            MainActor.assumeIsolated { [weak self] in self?.deliver(url) }
        }
    }

    /// Builds the callback URL from an origin-form (`/callback?...`) request target, or an
    /// absolute-form one when a proxy or filter intermediates loopback.
    nonisolated static func callbackURL(_ target: String, port: UInt16) -> URL? {
        guard port != 0 else { return nil }
        if target == "/callback" || target.hasPrefix("/callback?") {
            return URL(string: "http://127.0.0.1:\(port)\(target)")
        }
        guard let parsed = URL(string: target), parsed.scheme == "http",
            parsed.path == "/callback", parsed.port == Int(port),
            let host = parsed.host, ["127.0.0.1", "localhost", "::1"].contains(host)
        else { return nil }
        return parsed
    }

    /// The CSRF check gates delivery, not just the token exchange.
    nonisolated static func hasCodeAndState(_ url: URL, state: String) -> Bool {
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else {
            return false
        }
        let code = items.first { $0.name == "code" }?.value ?? ""
        return !code.isEmpty && items.first { $0.name == "state" }?.value == state
    }

    private func reply(_ connection: NWConnection, _ status: String, _ body: String, then: (@Sendable () -> Void)? = nil) {
        let payload = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        connection.send(content: Data(payload.utf8), completion: .contentProcessed { _ in
            connection.cancel()
            then?()
        })
    }

    private func deliver(_ url: URL) {
        guard !delivered else { return }
        delivered = true
        onURL?(url)
    }
}

private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func run(_ body: () -> Void) {
        lock.lock()
        let first = !done
        if first { done = true }
        lock.unlock()
        if first { body() }
    }
}
