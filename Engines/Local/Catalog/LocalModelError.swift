import Foundation

enum LocalModelError: Error, LocalizedError, Equatable {
    case invalidRepo(String)
    case invalidFilePath(String)
    case invalidResponse
    case http(status: Int)
    case notFound(String)
    case gatedOrPrivate(String)
    case noFiles(String)
    case insufficientSpace(neededBytes: Int64, freeBytes: Int64)
    case checksumMismatch(String)
    case sizeMismatch(String)
    case unsupportedCatalogVersion(Int)

    var errorDescription: String? {
        switch self {
        case .invalidRepo(let repo): "Not a Hugging Face repo id: \(repo)"
        case .invalidFilePath(let path): "Unsafe file path in repo listing: \(path)"
        case .invalidResponse: "Unexpected response from Hugging Face."
        case .http(let status): "Hugging Face answered HTTP \(status)."
        case .notFound(let what): "Not found on Hugging Face: \(what)"
        case .gatedOrPrivate(let repo): "\(repo) is gated or private. Accept its terms on huggingface.co first."
        case .noFiles(let repo): "No downloadable model files in \(repo)."
        case .insufficientSpace(let needed, let free):
            "Not enough free space: needs \(needed / 1_000_000) MB, \(free / 1_000_000) MB free."
        case .checksumMismatch(let path): "Checksum mismatch for \(path). Download it again."
        case .sizeMismatch(let path): "Size mismatch for \(path). Download it again."
        case .unsupportedCatalogVersion(let version): "Catalog schema version \(version) is newer than this app supports."
        }
    }
}
