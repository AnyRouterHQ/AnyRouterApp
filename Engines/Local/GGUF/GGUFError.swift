import Foundation

/// The file is bigger than the address space this install can map in one piece (a sideloaded build loses the extended
/// address space entitlement). Thrown before llama.cpp opens the file, so the reply says why instead of "failed to load".
struct GGUFMappingError: Error, LocalizedError, Equatable {
    var name: String
    var fileBytes: Int64
    var mappableBytes: Int64

    var errorDescription: String? {
        "Could not load \(name) (\(FitFormat.gigabytes(fileBytes))). " + FitText.addressSpaceReason(mappableBytes: mappableBytes)
    }
}

enum GGUFError: Error, LocalizedError, Equatable {
    case modelNotInstalled(String)
    /// `reason` is what llama.cpp logged while loading, nil when it said nothing.
    /// `log`: llama.cpp's last warning and error lines, shown behind the reply's Details.
    case loadFailed(name: String, reason: String?, log: [String] = [])
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
        case .loadFailed(let name, let reason, let log):
            "Could not load \(name). " + (reason.map { "llama.cpp said: \($0)" } ?? "The file may be damaged or too large for this device.")
                + (log.isEmpty ? "" : "\n\nllama.cpp log:\n" + log.joined(separator: "\n"))
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
