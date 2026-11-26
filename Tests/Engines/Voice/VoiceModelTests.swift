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
