import Foundation

/// Why the cloud reader would not or could not read an image, beyond the errors every AnyRouter call has.
enum AnyRouterOCRError: Error, Equatable, LocalizedError {
    case tooLarge

    var errorDescription: String? {
        "The image is over 5 MB, which is the most AnyRouter reads. Use a smaller photo."
    }
}

/// The request the cloud reader sends and the answer it reads. Pure, so the wire shape is tested without a network.
enum AnyRouterOCRWire {
    /// The largest image sent: 5 MiB, checked before anything is uploaded.
    static let maxBytes = 5 * 1024 * 1024

    private struct Body: Encodable {
        let image: String
        let filename: String?
    }

    private struct Answer: Decodable {
        let text: String
    }

    /// The type of the bytes from their first bytes. Anything unknown is sent as JPEG, the usual camera format.
    static func mimeType(of image: Data) -> String {
        let head = [UInt8](image.prefix(12))
        if head.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "image/png" }
        if head.starts(with: [0x25, 0x50, 0x44, 0x46]) { return "application/pdf" }
        if head.starts(with: [0x47, 0x49, 0x46]) { return "image/gif" }
        if head.count == 12, head.starts(with: [0x52, 0x49, 0x46, 0x46]), Array(head[8...]) == [0x57, 0x45, 0x42, 0x50] {
            return "image/webp"
        }
        return "image/jpeg"
    }

    static func body(image: Data, filename: String?) throws -> Data {
        guard image.count <= maxBytes else { throw AnyRouterOCRError.tooLarge }
        let url = "data:\(mimeType(of: image));base64,\(image.base64EncodedString())"
        return try JSONEncoder().encode(Body(image: url, filename: filename))
    }

    /// The Markdown the server read. Tables stay in it as Markdown rows.
    static func imageText(from data: Data) throws -> ImageText {
        guard let answer = try? JSONDecoder().decode(Answer.self, from: data) else { throw AnyRouterError.badResponse }
        return ImageText(text: answer.text)
    }
}

/// Reads an image on AnyRouter's servers (`POST /api/v1/ocr/extract`) with the signed-in key. The photo leaves the device,
/// so only the Extract screen offers this, behind a switch that is off by default; the `ocr_image` tool never gets it.
struct AnyRouterOCRReader: ImageTextReading {
    let engine: AnyRouterEngine
    var filename: String?

    func read(_ image: Data) async throws -> ImageText {
        guard let key = engine.tokens.token() else { throw AnyRouterError.signedOut }
        var http = URLRequest(url: engine.config.baseURL.appending(path: "ocr/extract"))
        http.httpMethod = "POST"
        http.httpBody = try AnyRouterOCRWire.body(image: image, filename: filename)
        http.timeoutInterval = 60
        http.setValue("application/json", forHTTPHeaderField: "Content-Type")
        http.setValue("application/json", forHTTPHeaderField: "Accept")
        engine.applyHeaders(&http, key: key)

        let (data, response) = try await engine.session.data(for: http)
        let status = AnyRouterError.status(of: response)
        if status == 401 {
            engine.tokens.clear()
            await engine.onUnauthorized()
            throw AnyRouterError.signedOut
        }
        if status == 413 { throw AnyRouterOCRError.tooLarge }
        guard (200..<300).contains(status) else {
            throw AnyRouterError.http(status: status, message: AnyRouterError.message(from: data, status: status))
        }
        return try AnyRouterOCRWire.imageText(from: data)
    }
}
