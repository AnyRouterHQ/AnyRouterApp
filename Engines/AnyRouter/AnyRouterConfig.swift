import Foundation

struct AnyRouterConfig: Sendable {
    var baseURL = URL(string: "https://anyrouter.dev/api/v1")!
    var origin = URL(string: "https://anyrouter.dev")!
    var clientName = "AnyRouter for iOS"
    /// Attribution: identifies this app in AnyRouter's app analytics.
    var referer = "https://github.com/AnyRouterHQ/AnyRouterApp"
    var source = "ios-app"
    var categories = "general-chat"

    var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    static let standard = AnyRouterConfig()
}

enum AnyRouterError: LocalizedError, Equatable {
    case signedOut
    case http(status: Int, message: String)
    case stream(String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .signedOut: return "Sign in with AnyRouter to use cloud models."
        case .http(_, let message): return message
        case .stream(let message): return message
        case .badResponse: return "AnyRouter returned an unexpected response."
        }
    }

    /// Pulls `error.message` (or OAuth `error_description`) out of an error body.
    static func message(from data: Data, status: Int) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = json["error"] as? [String: Any], let text = error["message"] as? String, !text.isEmpty {
                return text
            }
            if let text = json["error_description"] as? String, !text.isEmpty { return text }
            if let text = json["message"] as? String, !text.isEmpty { return text }
            if let text = json["error"] as? String, !text.isEmpty { return text }
        }
        return "Request failed (HTTP \(status))."
    }
}
