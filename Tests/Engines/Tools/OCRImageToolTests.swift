import Foundation
import Testing
@testable import AnyRouter

/// Reads the text it was given for each image's bytes, and counts the images it was asked to read.
private final class FakeImageReader: ImageTextReading, @unchecked Sendable {
    private let lock = NSLock()
    private var reads = 0
    let answers: [Data: ImageText]
    init(_ answers: [Data: ImageText]) { self.answers = answers }
    var count: Int { lock.withLock { reads } }
    func read(_ image: Data) async throws -> ImageText {
        lock.withLock { reads += 1 }
        return answers[image] ?? ImageText(text: "")
    }
}

private final class ImageFixtureAnchor {}

struct OCRImageToolTests {
    private let store = AttachmentStore(
        root: FileManager.default.temporaryDirectory.appending(path: "ocr-tool-\(UUID().uuidString)", directoryHint: .isDirectory))

    private func photo(_ name: String, bytes: String?) throws -> ChatAttachment {
        let id = UUID()
        let path = try bytes.map { try store.write(Data($0.utf8), id: id, fileExtension: "jpg") } ?? "gone/\(id).jpg"
        return ChatAttachment(id: id, kind: .image, filename: name, utType: "public.jpeg", byteCount: 1, relativePath: path)
    }

    private func run(_ tool: OCRImageTool, _ json: String = "{}") async throws -> String {
        try await tool.run(try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8)))
    }

    @Test func tablesBecomeMarkdownRowsUnderTheText() {
        let read = ImageText(text: " CAFE SAIGON \n", tables: [[["Item", "Price"], ["Pho bo", "65,000"], ["Tra"]]])
        #expect(read.rendered == """
            CAFE SAIGON

            Table 1:
            | Item | Price |
            | --- | --- |
            | Pho bo | 65,000 |
            | Tra |  |
            """)
        let odd = ImageText(text: "", tables: [[["a|b", "two\nlines"]]])
        #expect(odd.rendered == "Table 1:\n| a\\|b | two lines |\n| --- | --- |", "a pipe or a line break would split the row")
        #expect(ImageText(text: " \n").isEmpty)
        #expect(!ImageText(text: "", tables: [[["x"]]]).isEmpty)
    }

    @Test func withoutANameItReadsEachPhotoUnderItsName() async throws {
        let reader = FakeImageReader([Data("a".utf8): ImageText(text: "first"), Data("b".utf8): ImageText(text: "")])
        let tool = OCRImageTool(images: [try photo("a.jpg", bytes: "a"), try photo("b.jpg", bytes: "b")], store: store, reader: reader)
        #expect(try await run(tool) == "[a.jpg]\nfirst\n\n[b.jpg]\nNo text found.")
    }

    @Test func aNamedPhotoIsFoundWhateverItsCase() async throws {
        let reader = FakeImageReader([Data("a".utf8): ImageText(text: "first"), Data("b".utf8): ImageText(text: "second")])
        let tool = OCRImageTool(images: [try photo("a.jpg", bytes: "a"), try photo("Bill.jpg", bytes: "b")], store: store, reader: reader)
        #expect(try await run(tool, #"{"name":"bill.JPG"}"#) == "[Bill.jpg]\nsecond")
        #expect(reader.count == 1, "only the named photo is read")
        await #expect(throws: BuiltInToolError("No photo named x.jpg. Photos: a.jpg, Bill.jpg")) {
            try await run(tool, #"{"name":"x.jpg"}"#)
        }
    }

    @Test func aChatWithoutPhotosOrWithAMissingFileSaysSo() async throws {
        await #expect(throws: BuiltInToolError("There are no photos in this chat.")) {
            try await run(OCRImageTool(images: [], store: store, reader: FakeImageReader([:])))
        }
        let tool = OCRImageTool(images: [try photo("lost.jpg", bytes: nil)], store: store, reader: FakeImageReader([:]))
        #expect(try await run(tool) == "[lost.jpg]\nThe photo file is missing.")
    }

    @Test func manyPhotosReadTheNewestFourAndSaySo() async throws {
        var answers: [Data: ImageText] = [:]
        var images: [ChatAttachment] = []
        for index in 1...6 {
            answers[Data("\(index)".utf8)] = ImageText(text: "page \(index)")
            images.append(try photo("p\(index).jpg", bytes: "\(index)"))
        }
        let reader = FakeImageReader(answers)
        let text = try await run(OCRImageTool(images: images, store: store, reader: reader))
        #expect(reader.count == 4)
        #expect(text.hasPrefix("Read the newest 4 of 6 photos. Name one to read another.\n\n[p3.jpg]\npage 3"))
        #expect(text.hasSuffix("[p6.jpg]\npage 6"))
        #expect(!text.contains("p2.jpg"))
    }

    @Test func aLongReadIsCut() async throws {
        let reader = FakeImageReader([Data("a".utf8): ImageText(text: String(repeating: "x", count: 50))])
        var tool = OCRImageTool(images: [try photo("a.jpg", bytes: "a")], store: store, reader: reader)
        tool.maxCharacters = 20
        #expect(try await run(tool) == "[a.jpg]\n" + String(repeating: "x", count: 12) + "\n[Cut at 20 characters.]")
    }

    @Test func visionReadsTheReceiptPhoto() async throws {
        let url = try #require(Bundle(for: ImageFixtureAnchor.self).url(forResource: "receipt", withExtension: "png"))
        let read = try await VisionTextReader().read(try Data(contentsOf: url))
        #expect(read.text.contains("CAFE SAIGON"))
        #expect(read.text.contains("TOTAL") && read.text.contains("80,000"))
        let folded = read.rendered.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        #expect(folded.contains("cam on"), "Vietnamese line: \(read.rendered)")
        #expect(try await VisionTextReader().read(Data("not an image".utf8)).isEmpty)
    }
}
