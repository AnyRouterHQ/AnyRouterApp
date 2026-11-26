import Foundation

enum MLXAvailability: Equatable, Sendable {
    case available
    case unavailable(String)
}

enum MLXError: Error, LocalizedError, Equatable {
    case unavailable(String)
    case modelNotInstalled(String)
    case emptyConversation

    var errorDescription: String? {
        switch self {
        case .unavailable(let reason): reason
        case .modelNotInstalled(let id): "Model is not downloaded: \(id)"
        case .emptyConversation: "There is no message to answer."
        }
    }
}
