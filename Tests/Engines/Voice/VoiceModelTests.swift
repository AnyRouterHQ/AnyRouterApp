import Foundation
import Testing
@testable import AnyRouter

struct VoiceModelTests {
    @Test func theBundledCatalogDecodesAndPinsEveryFile() throws {
        let models = try BundledVoiceCatalog.load()
        #expect(!models.isEmpty)
        #expect(Set(models.map(\.id)).count == models.count, "ids must be unique")
        for model in models {
            #expect(!model.files.isEmpty, "\(model.id) needs files to download")
            #expect(model.files.reduce(0) { $0 + $1.sizeBytes } == model.sizeBytes, "\(model.id): size is the sum of its files")
            for file in model.files {
                #expect(file.url.absoluteString.range(of: "/resolve/[0-9a-f]{40}/", options: .regularExpression) != nil,
                        "\(file.path) must come from a commit, not a branch")
                if let sha = file.sha256 { #expect(sha.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil) }
            }
        }
    }

    @Test func theBundledWhisperModelsAreMultilingualAndDetectLanguage() throws {
        let whisper = try BundledVoiceCatalog.load().filter { $0.engine == .whisperKit }
        #expect(whisper.map(\.id) == ["whisper-tiny", "whisper-base", "whisper-small", "whisper-large-v3-turbo"])
        for model in whisper {
            #expect(model.kind == .stt && model.detectsLanguage && model.license == "MIT")
            #expect(model.supports(.vietnamese) && model.supports(VoiceLanguage("fr")))
        }
        let tiny = try #require(whisper.first)
        #expect(tiny.isWeak(for: .vietnamese) && !tiny.isWeak(for: .english))
    }

    @Test func theBundledNeuralVoiceIsOneFolderTheEngineLoadsOffline() throws {
        let model = try #require(try BundledVoiceCatalog.load().first { $0.engine == .ttsKit })
        #expect(model.id == "ttskit-qwen3-0.6b" && model.kind == .tts && model.license == "Apache-2.0")
        #expect(Set(model.languages) == Set(TTSKitLanguage.allCases.map(\.code)), "the list and the engine's mapping say the same")
        #expect(!model.supports(.vietnamese) && model.summary?.contains("Vietnamese") == true)
        #expect(model.sizeBytes < 1_500_000_000)
        #expect(model.files.allSatisfy { $0.sha256 != nil }, "every file is checked after download")
        // TTSKitConfig's layout for the 0.6B model, with the variants of Qwen3VariantDefaults (argmax-oss-swift 1.1.1).
        let layout = [
            "code_decoder": "W8A16-stateful", "multi_code_decoder": "W8A16-multifunction", "code_embedder": "W16A16",
            "multi_code_embedder": "W16A16", "text_projector": "W8A16", "speech_decoder": "W8A16-multifunction",
        ]
        for (component, variant) in layout {
            let prefix = "qwen3_tts/\(component)/12hz-0.6b-customvoice/\(variant)/"
            let inside = model.files.filter { $0.path.hasPrefix(prefix) }
            #expect(inside.contains { $0.path.hasSuffix(".mlmodelc/coremldata.bin") }, "\(component) needs a compiled model")
        }
        let others = model.files.filter { !$0.path.hasPrefix("qwen3_tts/") }.map(\.path)
        #expect(others == ["tokenizer.json", "tokenizer_config.json"], "the tokenizer sits at the folder root, so nothing is fetched at load time")
    }

    @Test func anInvalidCatalogIsRefused() {
        #expect(throws: VoiceCatalogError.unsupportedVersion(2)) { try VoiceCatalogDocument.decode(VoiceFixtures.catalogJSON(version: 2)) }
        #expect(throws: VoiceCatalogError.invalidID("Bad Id")) { try VoiceCatalogDocument.decode(VoiceFixtures.catalogJSON(id: "Bad Id")) }
        #expect(throws: VoiceCatalogError.invalidID("system")) { try VoiceCatalogDocument.decode(VoiceFixtures.catalogJSON(id: "system")) }
        #expect(throws: VoiceCatalogError.invalidFile("../x")) { try VoiceCatalogDocument.decode(VoiceFixtures.catalogJSON(path: "../x")) }
        #expect(throws: VoiceCatalogError.invalidFile("a/b.bin")) {
            try VoiceCatalogDocument.decode(VoiceFixtures.catalogJSON(url: "http://example.com/b.bin"))
        }
    }

    @Test func aMinimalEntryDecodesWithDefaults() throws {
        let model = try #require(try VoiceCatalogDocument.decode(VoiceFixtures.catalogJSON()).models.first)
        #expect(!model.detectsLanguage && model.weakLanguages.isEmpty && model.residentBytes == nil)
        #expect(model.files.count == 1)
    }

    @Test func aMissingBundleFileIsAnError() throws {
        let empty = try #require(Bundle(path: NSTemporaryDirectory()))
        #expect(throws: VoiceCatalogError.missingBundle) { try BundledVoiceCatalog.load(bundle: empty) }
    }

    @Test func languageSupportFollowsTheList() {
        let all = VoiceFixtures.model("any")
        let some = VoiceFixtures.model("some", languages: ["en", "vi"])
        #expect(all.supports(VoiceLanguage("th")))
        #expect(some.supports(.vietnamese) && !some.supports(VoiceLanguage("th")))
    }

    @Test func theLanguageLineNamesLanguagesOrCountsThem() {
        #expect(VoiceFixtures.model("any").languageSummary == "Many languages")
        var counted = VoiceFixtures.model("counted")
        counted.languageCount = 99
        #expect(counted.languageSummary == "99 languages")
        #expect(VoiceFixtures.model("two", languages: ["en", "vi"]).languageSummary.contains(","))
    }

    @Test func theSystemRowCoversEveryLanguageAndCostsNothing() {
        for kind in VoiceModelKind.allCases {
            let system = VoiceModel.system(kind)
            #expect(system.isSystem && system.sizeBytes == 0 && system.supports(VoiceLanguage("th")) && system.kind == kind)
        }
        #expect(VoiceModel.system(.stt).summary != VoiceModel.system(.tts).summary)
    }
}
