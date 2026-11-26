import AuthenticationServices
import Foundation
import UIKit

struct IssuedToken: Sendable {
    var accessToken: String
    var expiresAt: Date?
}

/// Authorization code + PKCE against AnyRouter's sign-in endpoints. Public client, no secret.
/// The access token is an `sk-ar-` key.
///
/// The server rejects custom URL schemes, and an https callback needs an associated
/// domain. So the browser is redirected to a loopback port and the web session is
/// cancelled once that listener has the code. PKCE stays in the app.
@MainActor
final class OAuthClient: NSObject, ASWebAuthenticationPresentationContextProviding {
    enum Failure: LocalizedError {
        case message(String)
        case cancelled

        var errorDescription: String? {
            switch self {
            case .message(let text): return text
            case .cancelled: return "Sign-in was cancelled."
            }
        }
    }

    /// Only so `ASWebAuthenticationSession` will start. The code does not arrive on it.
    private static let sessionScheme = "anyrouter-ios"

    private let config: AnyRouterConfig
    private let urlSession: URLSession
    private var webSession: ASWebAuthenticationSession?
    private var waiter: CallbackWaiter?

    init(config: AnyRouterConfig = .standard, urlSession: URLSession = .shared) {
        self.config = config
        self.urlSession = urlSession
    }

    func signIn() async throws -> IssuedToken {
        let state = try PKCE.makeVerifier()
        let loopback = LoopbackCallback(expectedState: state)
        defer { loopback.stop() }
        let port = try await loopback.start()
        let redirect = "http://127.0.0.1:\(port)/callback"
        let clientID = try await register(redirect: redirect)

        let verifier = try PKCE.makeVerifier()
        var components = URLComponents(url: config.baseURL.appending(path: "mcp/oauth/authorize"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirect),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "code_challenge", value: PKCE.challenge(for: verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ]
        guard let url = components.url else { throw Failure.message("Could not build the authorize URL.") }

        let callback = try await present(url, loopback: loopback)
        guard let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems else {
            throw Failure.message("Sign-in returned no parameters.")
        }
        func query(_ name: String) -> String? { items.first { $0.name == name }?.value }
        guard query("state") == state else { throw Failure.message("Sign-in state did not match.") }
        if let error = query("error") {
            throw Failure.message(query("error_description").map { "\(error): \($0)" } ?? error)
        }
        guard let code = query("code"), !code.isEmpty else { throw Failure.message("Sign-in returned no code.") }
        return try await exchange(code: code, verifier: verifier, clientID: clientID, redirect: redirect)
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            if let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) { return window }
            if let scene = scenes.first { return ASPresentationAnchor(windowScene: scene) }
            return ASPresentationAnchor()
        }
    }

    // MARK: Endpoints

    private func register(redirect: String) async throws -> String {
        let json = try await post("mcp/oauth/register", [
            "client_name": config.clientName,
            "redirect_uris": [redirect],
            "app_type": "signin",
            "origin_url": config.origin.absoluteString,
            "token_endpoint_auth_method": "none",
            "grant_types": ["authorization_code"],
            "response_types": ["code"],
        ])
        guard let clientID = json["client_id"] as? String, !clientID.isEmpty else {
            throw Failure.message("Registration returned no client id.")
        }
        return clientID
    }

    private func exchange(code: String, verifier: String, clientID: String, redirect: String) async throws -> IssuedToken {
        let json = try await post("mcp/oauth/token", [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirect,
            "client_id": clientID,
            "code_verifier": verifier,
        ])
        guard let token = json["access_token"] as? String, token.hasPrefix("sk-ar-") else {
            throw Failure.message("Sign-in returned no access token.")
        }
        let seconds = (json["expires_in"] as? NSNumber)?.doubleValue ?? (json["expires_in"] as? String).flatMap(Double.init)
        return IssuedToken(accessToken: token, expiresAt: seconds.map { Date().addingTimeInterval($0) })
    }

    private func post(_ path: String, _ body: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: config.baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await urlSession.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure.message(AnyRouterError.message(from: data, status: status))
        }
        return json
    }

    // MARK: Web session

    private func present(_ url: URL, loopback: LoopbackCallback) async throws -> URL {
        let waiter = CallbackWaiter()
        self.waiter = waiter
        defer {
            self.waiter = nil
            webSession = nil
        }
        return try await waiter.wait { [self] in
            let session = ASWebAuthenticationSession(url: url, callback: .customScheme(Self.sessionScheme)) { callbackURL, error in
                Task { @MainActor in
                    if let callbackURL {
                        waiter.finish(.success(callbackURL))
                        return
                    }
                    if loopback.delivered { return }
                    let ns = error as NSError?
                    let cancelled = ns?.domain == ASWebAuthenticationSessionError.errorDomain
                        && ns?.code == ASWebAuthenticationSessionError.canceledLogin.rawValue
                    if !cancelled {
                        // The session can report a non-matching redirect before the loopback
                        // listener accepts the code. Give that request a moment to win.
                        try? await Task.sleep(for: .seconds(1))
                        if loopback.delivered { return }
                    }
                    waiter.finish(.failure(cancelled ? Failure.cancelled : (error ?? Failure.message("Sign-in failed."))))
                }
            }
            loopback.onURL = { [weak self] callback in
                self?.webSession?.cancel()
                waiter.finish(.success(callback))
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            webSession = session
            if !session.start() {
                waiter.finish(.failure(Failure.message("Could not open the sign-in window.")))
            }
        }
    }
}

/// Resumes exactly once, from whichever of the web session or the loopback listener wins.
@MainActor
private final class CallbackWaiter {
    private var continuation: CheckedContinuation<URL, Error>?

    func wait(start: () -> Void) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            start()
        }
    }

    func finish(_ result: Result<URL, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }
}
