import Foundation
import ImageIO
import Testing
import UIKit
import UniformTypeIdentifiers
@testable import AnyRouter

/// Photos for local models: which sizes accept them, how a message becomes a prompt with images, how photos are scaled,
/// and what memory the projector adds. The llama.cpp calls themselves run in the model smoke.
struct VisionInputTests {
    private func photo(_ name: String = "a.jpg") -> ChatAttachment {
        ChatAttachment(
            id: UUID(), kind: .image, filename: name, utType: "public.jpeg", byteCount: 1, relativePath: "t/\(name)")
    }

    private func message(_ role: ChatMessage.Role, _ text: String, images: [ChatAttachment] = []) -> ChatMessage {
        ChatMessage(role: role, content: text, attachments: images)
    }

    // MARK: Prompt

    @Test func theLastUserMessageGetsOneMarkerPerPhotoBeforeItsText() {
        let built = VisionInput.prompt(
            from: [message(.user, "what is this?", images: [photo("a.jpg"), photo("b.jpg")])], systemPrompt: "Be brief.")
        #expect(built.images.count == 2)
        #expect(built.messages.map(\.role) == ["system", "user"])
        #expect(built.messages[1].content == "\(VisionInput.defaultMarker)\n\(VisionInput.defaultMarker)\nwhat is this?")
    }

    @Test func aPhotoWithoutTextStillGetsItsMarker() {
        let built = VisionInput.prompt(from: [message(.user, "", images: [photo()])], systemPrompt: nil)
        #expect(built.messages.map(\.content) == [VisionInput.defaultMarker])
    }

    @Test func photosOfEarlierTurnsStayTextSoOnlyTheNewOnesCostMemory() {
        var old = photo("old.jpg")
        old.extractedText = "TOTAL 12.50"
        old.isOCR = true
        let built = VisionInput.prompt(
            from: [message(.user, "receipt", images: [old]), message(.assistant, "ok"), message(.user, "and this?", images: [photo("new.jpg")])],
            systemPrompt: nil)
        #expect(built.images.map(\.filename) == ["new.jpg"])
        #expect(built.messages[0].content.contains("TOTAL 12.50"))
        #expect(!built.messages[0].content.contains(VisionInput.defaultMarker))
    }

    @Test func atMostFourPhotosGoInAndTheMessageSaysSo() {
        let many = (1...6).map { photo("p\($0).jpg") }
        let built = VisionInput.prompt(from: [message(.user, "all of them", images: many)], systemPrompt: nil)
        #expect(built.images.map(\.filename) == ["p3.jpg", "p4.jpg", "p5.jpg", "p6.jpg"], "the newest four")
        let text = built.messages[0].content
        #expect(text.components(separatedBy: VisionInput.defaultMarker).count - 1 == VisionInput.maxImages)
        #expect(text.contains("2 more images not sent"))
    }

    @Test func aMessageWithoutPhotosIsTheTextPrompt() {
        let messages = [message(.user, "hi")]
        let built = VisionInput.prompt(from: messages, systemPrompt: "S")
        #expect(built.images.isEmpty)
        #expect(built.messages == PromptBuilder.promptMessages(from: messages, systemPrompt: "S"))
    }

    @Test func onlyAPhotoInTheLastUserMessageSendsImages() {
        #expect(GGUFEngine.hasImages([message(.user, "x", images: [photo()])]))
        #expect(!GGUFEngine.hasImages([message(.user, "x", images: [photo()]), message(.assistant, "y"), message(.user, "z")]))
        #expect(!GGUFEngine.hasImages([]))
    }

    // MARK: Projector files

    @Test func aProjectorIsRecognizedByName() {
        #expect(VisionInput.isProjector(path: "mmproj-F16.gguf"))
        #expect(VisionInput.isProjector(path: "sub/gemma-4-E2B-it-mmproj.gguf"))
        #expect(!VisionInput.isProjector(path: "gemma-4-E2B-it-Q4_K_M.gguf"))
    }

    @Test func downloadingASizeWithPhotosAlsoFetchesItsProjectorAndTheModelStaysFirst() throws {
        var entry = sampleGGUF(repo: "org/m-GGUF", file: "m-Q4.gguf")
        entry.vision = CatalogVision(mmprojFile: "mmproj-m.gguf", mmprojSize: 900, imageSide: 768)
        let files = [HFFile(path: "mmproj-m.gguf", size: 900), HFFile(path: "m-Q4.gguf", size: 4_000), HFFile(path: "README.md", size: 1)]
        #expect(try RepoFiles.downloadPlan(for: entry, files: files).map(\.path) == ["m-Q4.gguf", "mmproj-m.gguf"])
        entry.vision = nil
        #expect(try RepoFiles.downloadPlan(for: entry, files: files).map(\.path) == ["m-Q4.gguf"])
    }

    @Test func aMissingProjectorFailsTheDownloadInsteadOfInstallingAModelThatCannotSee() {
        var entry = sampleGGUF(repo: "org/m-GGUF", file: "m-Q4.gguf")
        entry.vision = CatalogVision(mmprojFile: "mmproj-m.gguf", mmprojSize: 900, imageSide: nil)
        #expect(throws: LocalModelError.notFound("mmproj-m.gguf")) {
            try RepoFiles.downloadPlan(for: entry, files: [HFFile(path: "m-Q4.gguf", size: 4_000)])
        }
    }

    // MARK: Scaling

    @Test func theImageSideComesFromTheCatalogWithinBounds() {
        #expect(VisionInput.imageSide(for: nil) == VisionInput.defaultImageSide)
        #expect(VisionInput.imageSide(for: CatalogVision(mmprojFile: "m", mmprojSize: nil, imageSide: 896)) == 896)
        #expect(VisionInput.imageSide(for: CatalogVision(mmprojFile: "m", mmprojSize: nil, imageSide: 10)) == 224)
        #expect(VisionInput.imageSide(for: CatalogVision(mmprojFile: "m", mmprojSize: nil, imageSide: 100_000)) == 4096)
    }

    private func jpeg(width: Int, height: Int) -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return format
        }())
        return renderer.jpegData(withCompressionQuality: 0.9) { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    @Test func photosAreScaledDownToTheModelsInputSideAndNeverUp() throws {
        let store = AttachmentStore(root: makeTempDirectory())
        let big = jpeg(width: 2000, height: 1000)
        let small = jpeg(width: 300, height: 200)
        var bigPhoto = photo("big.jpg"), smallPhoto = photo("small.jpg")
        bigPhoto.relativePath = try store.write(big, id: bigPhoto.id, fileExtension: "jpg")
        smallPhoto.relativePath = try store.write(small, id: smallPhoto.id, fileExtension: "jpg")

        let scaled = try GGUFEngine.imageData([bigPhoto, smallPhoto], side: 768, store: store)
        let bigSize = try #require(ImageProcessing.pixelSize(of: scaled[0]))
        #expect(max(bigSize.width, bigSize.height) == 768)
        #expect(bigSize.width == 768 && bigSize.height == 384, "the aspect ratio stays")
        let smallSize = try #require(ImageProcessing.pixelSize(of: scaled[1]))
        #expect(smallSize.width == 300 && smallSize.height == 200, "a small photo is not enlarged")
    }

    @Test func aPhotoThatCannotBeReadIsAClearError() {
        let store = AttachmentStore(root: makeTempDirectory())
        #expect(throws: GGUFError.imageUnreadable) { try GGUFEngine.imageData([photo("gone.jpg")], side: 768, store: store) }
        #expect(GGUFError.imageUnreadable.errorDescription?.contains("photo") == true)
    }

    // MARK: Memory

    // The 2B-class dense model with a 0.2 GB projector, as in the catalog.
    private let small = ModelMemoryProfile(
        fileBytes: 1_000_000_000, fullKVBytesPerToken: 50_000, trainedContext: 32_768, activeFraction: nil,
        projectorBytes: 200_000_000)

    private func memory(_ gigabytes: Double) -> DeviceMemory {
        DeviceMemory(budgetBytes: Int64(gigabytes * 1_000_000_000), physicalBytes: 0)
    }

    @Test func theProjectorAndItsBuffersCountOnTopOfTheWeights() throws {
        let plain = FitPlanner.estimate(small, memory: memory(4))
        let withPhotos = try #require(FitPlanner.imageInputEstimate(small, memory: memory(4)))
        #expect(withPhotos.totalBytes == plain.totalBytes + 200_000_000 + FitPlanner.imageEncoderBytes)
    }

    @Test func aSizeCanRunWellForTextAndStillBeTooBigForPhotos() {
        // 1.0 GB of weights + 1 GB overhead + KV: fits 2.1 GB for text, not once 0.95 GB for the projector is added.
        var tight = small
        tight.projectorBytes = 700_000_000
        #expect(FitPlanner.estimate(tight, memory: memory(2.1)).verdict != .wontFit)
        #expect(FitPlanner.imageInput(tight, memory: memory(2.1)) == .wontFit)
        #expect(FitPlanner.imageInput(tight, memory: memory(4)) != .wontFit)
    }

    @Test func aModelWithoutAProjectorNeverAcceptsPhotos() {
        var text = small
        text.projectorBytes = 0
        #expect(FitPlanner.imageInput(text, memory: memory(64)) == .wontFit)
        #expect(FitPlanner.imageInputEstimate(text, memory: memory(64)) == nil)
    }

    @Test func theCatalogsProjectorSizeReachesTheFitProfile() {
        var entry = sampleGGUF()
        entry.vision = CatalogVision(mmprojFile: "mmproj.gguf", mmprojSize: 123, imageSide: nil)
        #expect(entry.memoryProfile?.projectorBytes == 123)
        entry.vision = nil
        #expect(entry.memoryProfile?.projectorBytes == 0)
    }

    // MARK: Which sizes show vision

    private func install(_ entry: CatalogEntry, files: [String], in storage: LocalModelStorage) throws {
        for path in files {
            let url = storage.partialFileURL(forEntryID: entry.id, path: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("data".utf8).write(to: url)
        }
        try ModelInstaller.verifyAndInstall(
            DownloadJobRecord(entry: entry, files: files.map { HFFile(path: $0, size: 4) }), storage: storage)
    }

    private func visionEntry(_ file: String = "m-Q4.gguf") -> CatalogEntry {
        CatalogEntry(
            repo: "org/m-GGUF", format: .gguf, file: file, title: "M", sizeBytes: 1_000_000_000,
            capabilities: ["chat", "vision"], vision: CatalogVision(mmprojFile: "mmproj-m.gguf", mmprojSize: 200_000_000, imageSide: 768))
    }

    @Test func anInstalledSizeShowsVisionOnlyWithItsProjectorOnDiskAndRoomForIt() throws {
        let entry = visionEntry()
        let withProjector = LocalModelStorage(root: makeTempDirectory())
        try install(entry, files: ["m-Q4.gguf", "mmproj-m.gguf"], in: withProjector)
        let roomy = LocalModelDescriptors.installed(format: .gguf, storage: withProjector, catalog: [entry], memory: memory(8))
        #expect(roomy.first?.capabilities.contains("vision") == true)

        let crowded = LocalModelDescriptors.installed(format: .gguf, storage: withProjector, catalog: [entry], memory: memory(1.5))
        #expect(crowded.first?.capabilities.contains("vision") == false, "no room for the projector on this device")

        let withoutProjector = LocalModelStorage(root: makeTempDirectory())
        try install(entry, files: ["m-Q4.gguf"], in: withoutProjector)
        let textOnly = LocalModelDescriptors.installed(format: .gguf, storage: withoutProjector, catalog: [entry], memory: memory(8))
        #expect(textOnly.first?.capabilities.contains("vision") == false, "installed before photos shipped: download again")
    }

    @Test func anEntryWithoutTheCapabilityStillShowsVisionOnceItsProjectorIsInstalled() throws {
        var entry = visionEntry()
        entry.capabilities = ["chat"]
        let storage = LocalModelStorage(root: makeTempDirectory())
        try install(entry, files: ["m-Q4.gguf", "mmproj-m.gguf"], in: storage)
        let installed = LocalModelDescriptors.installed(format: .gguf, storage: storage, catalog: [entry], memory: memory(8))
        #expect(installed.first?.capabilities.contains("vision") == true)
        #expect(entry.descriptor(isInstalled: false).capabilities == ["chat"], "not installed: the catalog's capabilities as they are")
    }

    @Test func aFamilyHasTheVisionTagOnlyWhenASizeTakesPhotos() throws {
        let family = try JSONDecoder().decode(CatalogFamily.self, from: Data("""
        {"id":"f","name":"F","publisher":"P","line":"f","logo":"f","summary":"S","website":"https://example.org",
         "tags":["vision","mobile"],"badges":[],"status":"current","variants":[
          {"repo":"o/a","engine":"gguf","file":"a.gguf","params":"1B","sizeBytes":1,"vision":{"mmprojFile":"mmproj.gguf"}},
          {"repo":"o/b","engine":"mlx","params":"1B","sizeBytes":1}]}
        """.utf8))
        let entries = family.entries(familyIndex: 0)
        #expect(entries[0].capabilities.contains("vision"))
        #expect(!entries[1].capabilities.contains("vision"), "the MLX size has no projector")
        #expect(entries[1].capabilities.contains("mobile"))
    }

    // MARK: Routing

    private func model(_ id: String, vision: Bool, installed: Bool = true) -> ModelDescriptor {
        ModelDescriptor(
            id: id, source: .gguf, displayName: id, contextLength: nil,
            capabilities: vision ? ["chat", "vision"] : ["chat"], sizeBytes: nil, isInstalled: installed)
    }

    @Test func aPhotoForATextOnlyModelSuggestsAVisionModelYouHave() {
        let text = model("text-model", vision: false)
        let sees = model("sees-model", vision: true)
        let models = [text, model("not-installed", vision: true, installed: false), sees]
        let note = AttachmentLogic.note(
            for: [photo()], model: text, alternative: AttachmentLogic.visionAlternative(in: models))
        #expect(note == "\(AttachmentLogic.visionNote) Try sees-model.")
    }

    @Test func withoutAVisionModelTheNoteStaysTheSameAndAVisionModelGetsNone() {
        let text = model("text-model", vision: false)
        #expect(AttachmentLogic.note(for: [photo()], model: text, alternative: nil) == AttachmentLogic.visionNote)
        #expect(AttachmentLogic.note(for: [photo()], model: model("v", vision: true), alternative: text) == nil)
        #expect(AttachmentLogic.visionAlternative(in: [model("v", vision: true, installed: false)]) == nil)
    }
}
