import Foundation

enum GGUFError: Error, LocalizedError, Equatable {
    case modelNotInstalled(String)
    case loadFailed(String)
    case contextFailed
    case tokenizeFailed
    case promptTooLong(tokens: Int, limit: Int)
    case decodeFailed(Int32)
    case wontFit(name: String, neededBytes: Int64, availableBytes: Int64)
    case projectorLoadFailed(String)
    case imageUnreadable
    case imageEncodeFailed(Int32)
    case imagesWontFit(name: String, neededBytes: Int64, availableBytes: Int64)
    case imagesNotSupported(String)

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
        case .projectorLoadFailed(let name): "Could not load the image reader (\(name)). Download the model again."
        case .imageUnreadable: "Could not read the photo. Try a JPEG or PNG."
        case .imageEncodeFailed(let code): "The model could not read the photo (code \(code))."
        case .imagesWontFit(let name, let needed, let available):
            "\(name) needs about \(FitFormat.gigabytes(needed)) of memory to read photos and this device can give about \(FitFormat.gigabytes(available)). Remove the photo or pick a smaller model."
        case .imagesNotSupported(let name): "\(name) cannot read photos. Pick a vision model."
        }
    }
}
