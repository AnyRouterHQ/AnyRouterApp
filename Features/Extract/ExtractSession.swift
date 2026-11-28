import Foundation
import Observation
import PDFKit
import UIKit

/// A photo or PDF the composer hands to Extract when it opens: the file the chat already has.
struct ExtractSeed: Equatable, Sendable {
    var data: Data
    var filename: String
    var isPDF: Bool
}

/// The state of one Extract screen: the document text, the fields to read, the model that reads them and the answers.
/// Images go through the same `ImageTextReading` the `ocr_image` tool uses. The model runs through `HeadlessChat`, one
/// non-streaming prompt, the same path the Shortcuts actions take.
@MainActor @Observable
final class ExtractSession {
    enum Phase: Equatable { case idle, reading, extracting }

    private(set) var text = ""
    private(set) var sourceName: String?
    private(set) var fields: [ExtractedField] = []
    private(set) var phase = Phase.idle
    var errorMessage: String?
    private(set) var presetID = "receipt"
    private(set) var customFields: [FieldSpec] = []
    /// Read images on AnyRouter's servers. Off by default; only offered when signed in.
    var usesCloudReader = false
    private(set) var selectedFieldID: String?
    /// The model the person picked for Extract (a wire id), remembered across launches.
    private var pickedID: String?
    private let picks: MiniAppModelPicks
    static let pickKey = "extract"

    var models: ModelStore?
    var deviceReader: any ImageTextReading = VisionTextReader()
    /// The cloud reader for a file name, or nil when signed out.
    var cloudReader: (String?) -> (any ImageTextReading)? = { _ in nil }
    var ask: @MainActor (String, String?) async throws -> String = { _, _ in throw HeadlessError.noModel }

    init(picks: MiniAppModelPicks = MiniAppModelPicks()) {
        self.picks = picks
        pickedID = picks.pick(for: Self.pickKey)
    }

    // MARK: What is on screen

    var preset: ExtractPreset { ExtractLogic.preset(id: presetID) ?? ExtractLogic.presets[0] }

    var activeFields: [FieldSpec] { preset.isCustom ? customFields : preset.fields }

    var lines: [DocumentLine] { ExtractLogic.lines(of: text) }

    var canExtract: Bool { phase == .idle && ExtractLogic.canExtract(text: text, fields: activeFields) }

    /// The model Extract will ask: the person's pick, else the preset's preferred model, else its fallback, else any chat
    /// model that can run now. Apple and local models count.
    var resolvedModel: ModelDescriptor? {
        guard let models else { return nil }
        return MiniAppModelChoice.choose(
            [pickedID, preset.preferredModel, preset.fallbackModel], from: models.listed(for: .chat))
    }

    /// The pick from the picker, remembered for Extract.
    func choose(_ model: ModelDescriptor) {
        pickedID = model.wireID
        picks.remember(model, for: Self.pickKey)
    }

    /// Said under the text while the model would get less than all of it.
    var cutNote: String? {
        guard let model = resolvedModel else { return nil }
        let limit = ExtractLogic.characterLimit(for: model.source)
        return text.count > limit ? ExtractLogic.cutNote(limit: limit, total: text.count) : nil
    }

    var sourceRanges: [Range<Int>] { fields.compactMap(\.source) }

    var selectedRange: Range<Int>? { fields.first { $0.id == selectedFieldID }?.source }

    // MARK: Choices

    func choosePreset(_ id: String) {
        guard id != presetID else { return }
        presetID = id
        clearAnswers()
    }

    func addCustomField(_ name: String) {
        customFields = ExtractLogic.adding(FieldSpec(name), to: customFields)
        clearAnswers()
    }

    func removeCustomFields(at offsets: IndexSet) {
        customFields.remove(atOffsets: offsets)
        clearAnswers()
    }

    func setKind(_ kind: FieldSpec.Kind, ofCustomField name: String) {
        guard let index = customFields.firstIndex(where: { $0.name == name }) else { return }
        customFields[index].kind = kind
        clearAnswers()
    }

    /// A tap on a row: its source is marked and scrolled to. A field without a source stays unselected.
    func select(_ id: String) {
        let hasSource = fields.contains { $0.id == id && $0.source != nil }
        selectedFieldID = hasSource ? id : nil
    }

    private func clearAnswers() {
        fields = []
        selectedFieldID = nil
    }

    // MARK: Documents

    func load(_ seed: ExtractSeed) async {
        if seed.isPDF { await load(pdf: seed.data, name: seed.filename) } else { await load(images: [seed.data], name: seed.filename) }
    }

    func load(file url: URL) async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            errorMessage = "The file could not be opened."
            return
        }
        await load(ExtractSeed(data: data, filename: url.lastPathComponent, isPDF: url.pathExtension.lowercased() == "pdf"))
    }

    func load(images: [Data], name: String) async {
        begin(name)
        defer { phase = .idle }
        await read(images, name: name)
    }

    /// The text layer when the PDF has one. A scan without it has its pages read as images.
    func load(pdf data: Data, name: String) async {
        begin(name)
        defer { phase = .idle }
        if let layer = TextExtraction.pdfText(data) {
            text = layer
        } else {
            await read(await PDFPageImages.render(data), name: name)
        }
    }

    private func begin(_ name: String) {
        sourceName = name
        text = ""
        errorMessage = nil
        clearAnswers()
        phase = .reading
    }

    private func read(_ images: [Data], name: String) async {
        let cloud = usesCloudReader ? cloudReader(name) : nil
        var parts: [String] = []
        do {
            for image in images {
                let result: ImageText
                if let cloud {
                    // The server reads JPEG and PNG within 5 MiB; a camera's HEIC at full size is neither.
                    result = try await cloud.read(ImageProcessing.jpeg(from: image, maxSide: 3000) ?? image)
                } else {
                    result = try await deviceReader.read(image)
                }
                if !result.isEmpty { parts.append(result.rendered) }
            }
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        text = OCRLogic.join(parts)
        if text.isEmpty { errorMessage = OCRLogic.noTextMessage }
    }

    /// Fills the screen from the canned demo data, for screenshots and UI tests.
    func applyDemo(stage: String) {
        guard stage != "empty" else { return }
        sourceName = Self.demoName
        text = Self.demoText
        guard stage == "fields" || stage == "selected" else { return }
        fields = (try? ExtractLogic.parse(Self.demoReply, fields: activeFields, in: text)) ?? []
        if stage == "selected" { select("Total") }
    }

    // MARK: Extract

    func extract() async {
        guard canExtract else { return }
        guard let model = resolvedModel else {
            errorMessage = HeadlessError.noModel.message
            return
        }
        let requested = activeFields
        let limit = ExtractLogic.characterLimit(for: model.source)
        let service = ExtractService(ask: ask, characterLimit: { _ in limit })
        errorMessage = nil
        clearAnswers()
        phase = .extracting
        defer { phase = .idle }
        do {
            fields = try await service.extract(text: text, fields: requested, modelID: model.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

enum PDFPageImages {
    /// Up to `limit` pages of a PDF drawn as PNG images, for a scan that has no text layer.
    @concurrent static func render(_ pdf: Data, limit: Int = 6) async -> [Data] {
        guard let document = PDFDocument(data: pdf) else { return [] }
        return (0..<min(document.pageCount, limit)).compactMap { index in
            guard let page = document.page(at: index) else { return nil }
            let bounds = page.bounds(for: .mediaBox)
            let scale = 2000 / max(bounds.width, bounds.height, 1)
            let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
            return page.thumbnail(of: size, for: .mediaBox).pngData()
        }
    }
}
