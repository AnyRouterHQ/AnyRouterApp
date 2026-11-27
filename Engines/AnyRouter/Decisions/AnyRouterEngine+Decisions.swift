import Foundation

extension AnyRouterEngine {
    /// Runs typed questions against a decision model. A 401 clears the key, like the chat stream.
    func runDecision(_ request: DecisionRequest) async throws -> DecisionResult {
        guard let key = tokens.token() else { throw AnyRouterError.signedOut }
        var http = URLRequest(url: config.baseURL.appending(path: "decisions"))
        http.httpMethod = "POST"
        http.httpBody = try request.jsonBody()
        http.timeoutInterval = 60
        http.setValue("application/json", forHTTPHeaderField: "Content-Type")
        http.setValue("application/json", forHTTPHeaderField: "Accept")
        applyHeaders(&http, key: key)

        let started = ContinuousClock.now
        let (data, response) = try await session.data(for: http)
        let elapsed = started.duration(to: .now)
        let status = AnyRouterError.status(of: response)
        if status == 401 {
            tokens.clear()
            await onUnauthorized()
            throw AnyRouterError.signedOut
        }
        guard (200..<300).contains(status) else {
            let message = AnyRouterError.message(from: data, status: status)
            if status == 400, DecisionRunError.isImageRejection(data) { throw DecisionRunError.imagesRefused(serverMessage: message) }
            throw AnyRouterError.http(status: status, message: message)
        }
        var result = try DecisionResult.parse(data, for: request)
        result.latency = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        return result
    }
}
