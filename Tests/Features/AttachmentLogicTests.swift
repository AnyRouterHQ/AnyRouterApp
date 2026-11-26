import Foundation
import Testing
import UniformTypeIdentifiers
@testable import AnyRouter

struct AttachmentLogicTests {
    @Test func typesMapToKinds() {
        #expect(AttachmentLogic.kind(forUTType: "public.jpeg") == .image)
        #expect(AttachmentLogic.kind(forUTType: "public.heic") == .image)
        #expect(AttachmentLogic.kind(forUTType: "com.adobe.pdf") == .pdf)
        #expect(AttachmentLogic.kind(forUTType: "public.mp3") == .audio)
        for type in ["public.plain-text", "public.json", "public.comma-separated-values-text", "public.swift-source",
                     "public.xml"] {
            #expect(AttachmentLogic.kind(forUTType: type) == .text, "\(type)")
        }
        #expect(AttachmentLogic.kind(forUTType: "public.zip-archive") == nil)
        #expect(AttachmentLogic.kind(forUTType: "not a type") == nil)
    }

    @Test func anUnknownTypeFallsBackToAKnownTextExtension() {
        #expect(AttachmentLogic.kind(forUTType: "dyn.ah62d4rv4ge81g6xy", fileExtension: "MD") == .text)
        #expect(AttachmentLogic.kind(forUTType: nil, fileExtension: "swift") == .text)
        #expect(AttachmentLogic.kind(forUTType: "public.jpeg", fileExtension: "md") == .image)
        #expect(AttachmentLogic.kind(forUTType: nil, fileExtension: "zip") == nil)
    }

    @Test func theImporterOffersThePromisedTypes() {
        let types = AttachmentLogic.importableTypes
        for type in [UTType.pdf, .plainText, .commaSeparatedText, .json, .sourceCode, .image] {
            #expect(types.contains(type))
        }
    }

    @Test func everyKindHasAnIconAndSizesAreReadable() {
        let icons = [Attachment.Kind.image, .pdf, .text, .audio].map(AttachmentLogic.systemImage(for:))
        #expect(Set(icons).count == 4)
        #expect(AttachmentLogic.sizeText(2_048).contains("KB"))
    }

    @Test func longTextIsCutAtTheCap() {
        let short = AttachmentLogic.capped("abc")
        #expect(short.text == "abc" && !short.truncated)
        let long = AttachmentLogic.capped(String(repeating: "a", count: AttachmentPrompt.maxCharacters + 5))
        #expect(long.text.count == AttachmentPrompt.maxCharacters && long.truncated)
        let exact = AttachmentLogic.capped(String(repeating: "a", count: AttachmentPrompt.maxCharacters))
        #expect(!exact.truncated)
    }

    @Test func imagesFitTheLongSideAndNeverGrow() {
        #expect(AttachmentLogic.fittedSize(width: 4096, height: 2048) == (2048, 1024))
        #expect(AttachmentLogic.fittedSize(width: 1000, height: 3000) == (683, 2048))
        #expect(AttachmentLogic.fittedSize(width: 800, height: 600) == (800, 600))
        #expect(AttachmentLogic.fittedSize(width: 0, height: 0) == (0, 0))
        #expect(AttachmentLogic.fittedSize(width: 5000, height: 1) == (2048, 1))
    }

    @Test func namesLoseFolderPartsAndFallBackWhenEmpty() {
        #expect(AttachmentLogic.displayName("../etc/notes.txt", fallback: "File") == "notes.txt")
        #expect(AttachmentLogic.displayName("  ", fallback: "File") == "File")
        #expect(AttachmentLogic.displayName("a.pdf", fallback: "File") == "a.pdf")
    }

    private func model(_ id: String, vision: Bool, installed: Bool = true) -> ModelDescriptor {
        ModelDescriptor(id: id, source: .anyrouter, displayName: id, contextLength: nil,
                        capabilities: vision ? ["chat", "vision"] : ["chat"], sizeBytes: nil, isInstalled: installed)
    }

    @Test func theVisionNoteAppearsOnlyForPhotosAndATextOnlyModel() {
        let photo = [sampleAttachment(.image)]
        let file = [sampleAttachment(.text)]
        #expect(AttachmentLogic.note(for: photo, model: model("a", vision: false)) == AttachmentLogic.visionNote)
        #expect(AttachmentLogic.note(for: photo, model: model("a", vision: true)) == nil)
        #expect(AttachmentLogic.note(for: file, model: model("a", vision: false)) == nil)
        #expect(AttachmentLogic.note(for: photo, model: nil) == nil)
        #expect(AttachmentLogic.hasImage(photo) && !AttachmentLogic.hasImage(file))
    }

    @Test func aVisionModelIsOfferedOnlyWhenUsable() {
        let models = [model("text", vision: false), model("locked", vision: true, installed: false), model("eyes", vision: true)]
        #expect(AttachmentLogic.visionAlternative(in: models)?.id == "eyes")
        #expect(AttachmentLogic.visionAlternative(in: [models[0], models[1]]) == nil)
    }

    @Test func visionComesFromTheTagOrTheCatalogInfo() {
        var seen = model("a", vision: false)
        #expect(!seen.supportsVision)
        seen.cloud = CloudInfo(
            pricing: CloudPricing(input: nil, output: nil, cacheRead: nil, billing: .unknown), availability: .usable,
            upstreamCount: nil, memberCount: nil, supportsVision: true, supportsReasoning: false, created: nil, logoURL: nil)
        #expect(seen.supportsVision)
    }
}
