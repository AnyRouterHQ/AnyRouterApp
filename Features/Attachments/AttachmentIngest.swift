import Foundation
import ImageIO
import PDFKit
import UIKit
import UniformTypeIdentifiers
import Vision

enum AttachmentError: LocalizedError, Equatable {
    case unreadable(String)
    case unsupported(String)
    case tooLarge(String)

    var errorDescription: String? {
        switch self {
        case .unreadable(let name): "Could not read \(name)."
        case .unsupported(let name): "\(name) is not a type the app can read."
        case .tooLarge(let name): "\(name) is larger than \(AttachmentLogic.sizeText(AttachmentLogic.maxFileBytes))."
        }
    }
}

/// Turns a picked photo or file into a stored `ChatAttachment`: images are shrunk to JPEG, text is read on device.
/// All of it runs off the main actor.
enum AttachmentIngest {
    /// A photo or camera image, as the bytes the system gave us (HEIC, PNG, JPEG).
    @concurrent static func image(from data: Data, filename: String, store: AttachmentStore) async throws -> ChatAttachment {
        let name = AttachmentLogic.displayName(filename, fallback: "Photo.jpg")
        guard let jpeg = ImageProcessing.jpeg(from: data, maxSide: AttachmentLogic.maxImageSide) else {
            throw AttachmentError.unreadable(name)
        }
        let id = UUID()
        let path = try store.write(jpeg, id: id, fileExtension: "jpg")
        let ocr = TextExtraction.ocr(jpeg)
        let capped = ocr.map(AttachmentLogic.capped)
        return ChatAttachment(
            id: id, kind: .image, filename: Self.jpegName(name), utType: UTType.jpeg.identifier,
            byteCount: Int64(jpeg.count), relativePath: path,
            extractedText: capped?.text, isOCR: capped != nil, isTruncated: capped?.truncated ?? false)
    }

    /// A file from the Files importer. The URL is security scoped.
    @concurrent static func file(
        at url: URL, store: AttachmentStore, maxBytes: Int64 = AttachmentLogic.maxFileBytes
    ) async throws -> ChatAttachment {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let name = AttachmentLogic.displayName(url.lastPathComponent, fallback: "File")
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
            ?? UTType(filenameExtension: url.pathExtension)
        let typeID = type?.identifier ?? UTType.data.identifier
        guard let kind = AttachmentLogic.kind(forUTType: type?.identifier, fileExtension: url.pathExtension) else {
            throw AttachmentError.unsupported(name)
        }
        // The whole file is read into memory (and parsed), so a huge one is refused before it is opened.
        if let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, Int64(size) > maxBytes {
            throw AttachmentError.tooLarge(name)
        }
        guard let data = try? Data(contentsOf: url) else { throw AttachmentError.unreadable(name) }
        switch kind {
        case .image:
            return try await image(from: data, filename: name, store: store)
        case .pdf:
            let id = UUID()
            let path = try store.write(data, id: id, fileExtension: "pdf")
            let capped = TextExtraction.pdfText(data).map(AttachmentLogic.capped)
            return ChatAttachment(
                id: id, kind: .pdf, filename: name, utType: typeID, byteCount: Int64(data.count),
                relativePath: path, extractedText: capped?.text, isTruncated: capped?.truncated ?? false)
        case .text:
            guard let text = TextExtraction.plainText(data) else { throw AttachmentError.unreadable(name) }
            let id = UUID()
            let path = try store.write(data, id: id, fileExtension: url.pathExtension)
            let capped = AttachmentLogic.capped(text)
            return ChatAttachment(
                id: id, kind: .text, filename: name, utType: typeID, byteCount: Int64(data.count),
                relativePath: path, extractedText: capped.text, isTruncated: capped.truncated)
        case .audio:
            let id = UUID()
            let path = try store.write(data, id: id, fileExtension: url.pathExtension)
            return ChatAttachment(
                id: id, kind: .audio, filename: name, utType: typeID, byteCount: Int64(data.count),
                relativePath: path)
        }
    }

    private static func jpegName(_ name: String) -> String {
        let stem = (name as NSString).deletingPathExtension
        return (stem.isEmpty ? "Photo" : stem) + ".jpg"
    }
}

enum ImageProcessing {
    /// Re-encodes as JPEG no larger than `maxSide` on its longest side. Applies the EXIF orientation,
    /// so HEIC photos come out upright. `nil` when the bytes are not an image.
    static func jpeg(from data: Data, maxSide: Int, quality: Double = 0.85) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSide,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    /// Pixel size of an image file, without decoding it.
    static func pixelSize(of data: Data) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return (width, height)
    }

    /// A small preview for a chip or a bubble.
    static func thumbnail(at url: URL, maxSide: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSide,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary).map(UIImage.init(cgImage:))
    }
}

enum TextExtraction {
    /// Text of every page. `nil` for a scan without a text layer.
    static func pdfText(_ data: Data) -> String? {
        guard let text = PDFDocument(data: data)?.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return nil }
        return text
    }

    /// UTF-8, or Latin-1 as a fallback. `nil` for binary data.
    static func plainText(_ data: Data) -> String? {
        let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
        guard let text, !text.contains("\u{0}") else { return nil }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Text Vision finds in an image, one line per row. `nil` when there is none or OCR is unavailable.
    static func ocr(_ imageData: Data) -> String? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(data: imageData)
        guard (try? handler.perform([request])) != nil else { return nil }
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
