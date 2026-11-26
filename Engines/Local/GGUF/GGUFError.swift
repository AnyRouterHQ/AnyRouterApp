import Foundation

enum GGUFError: Error, LocalizedError, Equatable {
    case modelNotInstalled(String)
    case loadFailed(String)
    case contextFailed
    case tokenizeFailed
    case promptTooLong(tokens: Int, limit: Int)
    case decodeFailed(Int32)
    case wontFit(name: String, neededBytes: Int64, availableBytes: Int64)

    var errorDescription: String? {
        switch self {
        case .modelNotInstalled(let id): "Model is not downloaded: \(id)"
        case .loadFailed(let name): "Could not load \(name). The file may be damaged or too large for this device."
        case .contextFailed: "Could not allocate memory for the chat. Try a smaller model."
        case .tokenizeFailed: "Could not read the prompt."
        case .promptTooLong(let tokens, let limit): "The message needs \(tokens) tokens, the model reads \(limit) at most."
        case .decodeFailed(let code): "The model stopped with an error (code \(code))."
        case .wontFit(let name, let needed, let available):
            "\(name) needs about \(FitFormat.gigabytes(needed)) of memory and this device can give about \(FitFormat.gigabytes(available)). Pick a smaller model or a smaller quantization."
        }
    }
}
