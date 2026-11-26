import Foundation

/// Scripted HTTP for URLSession-based code. Each test uses its own host, so tests run in parallel.
final class StubRegistry: @unchecked Sendable {
    static let shared = StubRegistry()

    struct Reply: Sendable {
        var status = 200
        var body = Data()
        /// Keep the connection open after the body, like a slow stream.
        var hangs = false
        /// Answer with a plain URLResponse instead of an HTTPURLResponse.
        var nonHTTP = false
    }

    private let lock = NSLock()
    private var handlers: [String: @Sendable (URLRequest) -> Reply] = [:]
    private var stopped: Set<String> = []

    func register(host: String, handler: @escaping @Sendable (URLRequest) -> Reply) {
        lock.withLock { handlers[host] = handler }
    }

    func handler(host: String) -> (@Sendable (URLRequest) -> Reply)? {
        lock.withLock { handlers[host] }
    }

    func markStopped(host: String) { lock.withLock { _ = stopped.insert(host) } }
    func wasStopped(host: String) -> Bool { lock.withLock { stopped.contains(host) } }
}

final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    private var hanging = false

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let host = request.url?.host, let handler = StubRegistry.shared.handler(host: host) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        let reply = handler(request)
        let response: URLResponse = reply.nonHTTP
            ? URLResponse(url: request.url!, mimeType: nil, expectedContentLength: 0, textEncodingName: nil)
            : HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.body)
        if reply.hangs {
            hanging = true
        } else {
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {
        if hanging, let host = request.url?.host { StubRegistry.shared.markStopped(host: host) }
    }
}

/// A URLSession wired to a stub, plus a config that points the AnyRouter engine at it.
struct StubbedAPI {
    let host = "t-\(UUID().uuidString.lowercased()).test"
    let session: URLSession

    init(_ handler: @escaping @Sendable (URLRequest) -> StubRegistry.Reply) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        session = URLSession(configuration: configuration)
        StubRegistry.shared.register(host: host, handler: handler)
    }

    var config: AnyRouterConfig {
        AnyRouterConfig(baseURL: URL(string: "https://\(host)/api/v1")!)
    }
}
