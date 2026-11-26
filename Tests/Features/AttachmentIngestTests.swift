import Foundation
import Testing
import UIKit
@testable import AnyRouter

func pngData(width: Int, height: Int) -> Data {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).pngData { context in
        UIColor.systemTeal.setFill()
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    }
}

private func write(_ data: Data, named name: String) throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appending(path: "in-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let url = folder.appending(path: name)
    try data.write(to: url)
    return url
}

struct ImageProcessingTests {
    @Test func aLargePhotoIsShrunkToTheLongSideAndStoredAsJPEG() throws {
        let jpeg = try #require(ImageProcessing.jpeg(from: pngData(width: 3000, height: 1500), maxSide: AttachmentLogic.maxImageSide))
        #expect(Array(jpeg.prefix(2)) == [0xFF, 0xD8])
        let size = try #require(ImageProcessing.pixelSize(of: jpeg))
        #expect(size.width == 2048 && size.height == 1024)
    }

    @Test func aSmallPhotoKeepsItsShape() throws {
        let jpeg = try #require(ImageProcessing.jpeg(from: pngData(width: 400, height: 200), maxSide: 2048))
        let size = try #require(ImageProcessing.pixelSize(of: jpeg))
        #expect(size.width <= 2048 && size.width == size.height * 2)
    }

    @Test func aHEICPhotoComesOutAsJPEG() throws {
        // The Simulator has no HEIC encoder on some systems; then there is nothing to convert.
        guard let image = UIImage(data: pngData(width: 600, height: 400)), let heic = image.heicData() else { return }
        let jpeg = try #require(ImageProcessing.jpeg(from: heic, maxSide: 2048))
        #expect(Array(jpeg.prefix(2)) == [0xFF, 0xD8])
    }

    @Test func bytesThatAreNotAnImageGiveNothing() {
        #expect(ImageProcessing.jpeg(from: Data("nope".utf8), maxSide: 100) == nil)
        #expect(ImageProcessing.pixelSize(of: Data("nope".utf8)) == nil)
    }

    @Test func thumbnailsAreSmallAndMissingFilesGiveNothing() throws {
        let url = try write(pngData(width: 1200, height: 600), named: "t.png")
        let thumb = try #require(ImageProcessing.thumbnail(at: url, maxSide: 120))
        #expect(max(thumb.cgImage?.width ?? 0, thumb.cgImage?.height ?? 0) <= 120)
        #expect(ImageProcessing.thumbnail(at: URL(filePath: "/nonexistent.png"), maxSide: 120) == nil)
    }
}

struct TextExtractionTests {
    @Test func plainTextIsUTF8WithALatin1FallbackAndNeverBinary() {
        #expect(TextExtraction.plainText(Data("  héllo \n".utf8)) == "héllo")
        #expect(TextExtraction.plainText(Data([0xE9])) == "é")
        #expect(TextExtraction.plainText(Data([0x41, 0x00, 0x42])) == nil)
    }

    @Test func aPDFGivesItsTextAndABlankOneGivesNothing() throws {
        #expect(TextExtraction.pdfText(pdf(text: "Hello PDF"))?.contains("Hello PDF") == true)
        #expect(TextExtraction.pdfText(pdf(text: nil)) == nil)
        #expect(TextExtraction.pdfText(Data("not a pdf".utf8)) == nil)
    }

    @Test func aPlainPictureHasNoTextToRead() {
        #expect(TextExtraction.ocr(pngData(width: 200, height: 100)) == nil)
        #expect(TextExtraction.ocr(Data("nope".utf8)) == nil)
    }
}

func pdf(text: String?) -> Data {
    UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 400, height: 400)).pdfData { context in
        context.beginPage()
        if let text { (text as NSString).draw(at: CGPoint(x: 40, y: 40), withAttributes: [.font: UIFont.systemFont(ofSize: 24)]) }
    }
}

struct AttachmentIngestTests {
    @Test func aPhotoIsStoredAsASmallJPEGWithItsNameKept() async throws {
        let temp = TempAttachments()
        defer { temp.cleanup() }
        let attachment = try await AttachmentIngest.image(from: pngData(width: 3000, height: 1500), filename: "shot.png", store: temp.store)
        #expect(attachment.kind == .image && attachment.filename == "shot.jpg" && attachment.utType == "public.jpeg")
        #expect(temp.exists(attachment))
        let stored = try #require(temp.store.data(for: attachment))
        #expect(attachment.byteCount == Int64(stored.count))
        #expect(try #require(ImageProcessing.pixelSize(of: stored)).width == 2048)
        #expect(attachment.extractedText == nil && !attachment.isOCR)
    }

    @Test func aPhotoWithoutANameGetsOne() async throws {
        let temp = TempAttachments()
        defer { temp.cleanup() }
        let attachment = try await AttachmentIngest.image(from: pngData(width: 50, height: 50), filename: "", store: temp.store)
        #expect(attachment.filename == "Photo.jpg")
        let dotted = try await AttachmentIngest.image(from: pngData(width: 50, height: 50), filename: ".png", store: temp.store)
        #expect(dotted.filename.hasSuffix(".jpg"))
    }

    @Test func bytesThatAreNotAPhotoAreRejectedByName() async {
        let temp = TempAttachments()
        defer { temp.cleanup() }
        await #expect(throws: AttachmentError.unreadable("x.jpg")) {
            try await AttachmentIngest.image(from: Data("nope".utf8), filename: "x.jpg", store: temp.store)
        }
    }

    @Test func textFilesKeepTheirTextAndTypes() async throws {
        let temp = TempAttachments()
        defer { temp.cleanup() }
        for name in ["notes.txt", "data.csv", "config.json", "main.swift"] {
            let url = try write(Data("  line one\nline two \n".utf8), named: name)
            let attachment = try await AttachmentIngest.file(at: url, store: temp.store)
            #expect(attachment.kind == .text, "\(name)")
            #expect(attachment.extractedText == "line one\nline two")
            #expect(attachment.filename == name && !attachment.isTruncated && !attachment.isOCR)
            #expect(temp.exists(attachment))
        }
    }

    @Test func aHugeTextFileIsCutAtTheCapAndSaysSo() async throws {
        let temp = TempAttachments()
        defer { temp.cleanup() }
        let url = try write(Data(String(repeating: "a", count: 150_000).utf8), named: "big.txt")
        let attachment = try await AttachmentIngest.file(at: url, store: temp.store)
        #expect(attachment.extractedText?.count == AttachmentPrompt.maxCharacters)
        #expect(attachment.isTruncated)
        #expect(attachment.byteCount == 150_000)
    }

    @Test func aPDFKeepsItsTextAndFileSize() async throws {
        let temp = TempAttachments()
        defer { temp.cleanup() }
        let attachment = try await AttachmentIngest.file(at: try write(pdf(text: "Quarterly report"), named: "q.pdf"), store: temp.store)
        #expect(attachment.kind == .pdf && attachment.extractedText?.contains("Quarterly report") == true)
        let scan = try await AttachmentIngest.file(at: try write(pdf(text: nil), named: "scan.pdf"), store: temp.store)
        #expect(scan.kind == .pdf && scan.extractedText == nil)
    }

    @Test func aPhotoFileGoesThroughTheImagePath() async throws {
        let temp = TempAttachments()
        defer { temp.cleanup() }
        let attachment = try await AttachmentIngest.file(at: try write(pngData(width: 3000, height: 3000), named: "big.png"), store: temp.store)
        #expect(attachment.kind == .image && attachment.filename == "big.jpg")
        #expect(try #require(ImageProcessing.pixelSize(of: try #require(temp.store.data(for: attachment)))).width == 2048)
    }

    @Test func audioIsStoredButNotRead() async throws {
        let temp = TempAttachments()
        defer { temp.cleanup() }
        let attachment = try await AttachmentIngest.file(at: try write(Data([1, 2, 3, 4]), named: "memo.m4a"), store: temp.store)
        #expect(attachment.kind == .audio && attachment.extractedText == nil && temp.exists(attachment))
    }

    @Test func filesWeCannotReadAreRefusedByName() async throws {
        let temp = TempAttachments()
        defer { temp.cleanup() }
        let zip = try write(Data([1, 2]), named: "a.zip")
        await #expect(throws: AttachmentError.unsupported("a.zip")) { try await AttachmentIngest.file(at: zip, store: temp.store) }
        let odd = try write(Data([1, 2]), named: "a.zzzz")
        await #expect(throws: AttachmentError.unsupported("a.zzzz")) { try await AttachmentIngest.file(at: odd, store: temp.store) }
        let binary = try write(Data([0x41, 0x00, 0x42]), named: "bin.txt")
        await #expect(throws: AttachmentError.unreadable("bin.txt")) { try await AttachmentIngest.file(at: binary, store: temp.store) }
        let missing = URL(filePath: "/nonexistent/gone.txt")
        await #expect(throws: AttachmentError.unreadable("gone.txt")) { try await AttachmentIngest.file(at: missing, store: temp.store) }
    }

    @Test func errorsReadAsASentence() {
        #expect(AttachmentError.unreadable("a.pdf").errorDescription == "Could not read a.pdf.")
        #expect(AttachmentError.unsupported("a.zip").errorDescription == "a.zip is not a type the app can read.")
    }
}
