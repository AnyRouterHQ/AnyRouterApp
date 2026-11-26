import Foundation
import Testing
@testable import AnyRouter

struct VoiceModelsRulesTests {
    private let wanted: [VoiceLanguage] = [.english, .vietnamese]

    private func row(
        _ model: VoiceModel, _ state: ModelDownloadState = .notInstalled, _ verdict: VoiceFit.Verdict = .runsWell,
        isDefault: Bool = false, recommended: Bool = false
    ) -> VoiceModelsRules.Row {
        VoiceModelsRules.row(model, state: state, verdict: verdict, isDefault: isDefault, isRecommended: recommended, wanted: wanted)
    }

    @Test func theSystemRowCannotBeGottenOrDeletedAndIsSelectableUnlessDefault() {
        let system = VoiceModel.system(.stt)
        let notDefault = row(system, .installed, .system)
        #expect(notDefault.canSelect && !notDefault.canGet && !notDefault.canDelete && notDefault.note == nil)
        #expect(notDefault.detail == system.summary)
        #expect(!row(system, .installed, .system, isDefault: true).canSelect)
    }

    @Test func aModelThatIsNotOnTheDeviceOffersGetAndNothingElse() {
        let model = VoiceFixtures.model("whisper-small", size: 217_000_000)
        let r = row(model, recommended: true)
        #expect(r.canGet && !r.canSelect && !r.canDelete && r.isRecommended)
        #expect(r.detail == "Many languages · 217 MB · MIT")
    }

    @Test func aModelThatWillNotFitCannotBeGotAndSaysSo() {
        let r = row(VoiceFixtures.model("big"), .notInstalled, .wontFit)
        #expect(!r.canGet && r.note == "Will not fit")
    }

    @Test func aTightModelIsOfferedWithAWarning() {
        let r = row(VoiceFixtures.model("m"), .notInstalled, .tight)
        #expect(r.canGet && r.note == "Tight on this device")
    }

    @Test func anInstalledModelCanBeDefaultedAndDeletedAndIsNoLongerRecommended() {
        let model = VoiceFixtures.model("m")
        let r = row(model, .installed, .runsWell, recommended: true)
        #expect(r.canSelect && r.canDelete && !r.canGet && !r.isRecommended && r.note == nil)
        let current = row(model, .installed, .runsWell, isDefault: true)
        #expect(!current.canSelect && current.isDefault)
    }

    @Test func aFailedDownloadShowsItsReasonAndOffersRetryAndDelete() {
        let r = row(VoiceFixtures.model("m"), .failed("Checksum mismatch for a.bin. Download it again."))
        #expect(r.note == "Checksum mismatch for a.bin. Download it again." && r.canGet && r.canDelete)
    }

    @Test func aDownloadInFlightOffersNothingToTapExceptCancel() {
        let r = row(VoiceFixtures.model("m"), .downloading(received: 5, total: 10))
        #expect(!r.canGet && !r.canSelect && !r.canDelete)
    }

    @Test func theRowSaysWhichLanguagesGoToTheSystem() {
        let tiny = VoiceFixtures.model("tiny", weak: ["vi"])
        #expect(row(tiny, .installed).note == "Uses the System engine for Vietnamese")
        let voice = VoiceFixtures.model("voice", kind: .tts, languages: ["en"])
        #expect(row(voice, .installed).note == "Uses the System voice for Vietnamese")
        #expect(row(voice, .notInstalled, .wontFit).note == "Will not fit", "the fit matters more than languages for a model that cannot run")
    }

    @Test func theLanguagesToMentionAreEnglishVietnameseAndTheDevices() {
        #expect(VoiceModelsRules.wantedLanguages(deviceLanguages: ["fr-FR"]) == [.english, .vietnamese, VoiceLanguage("fr")])
    }

    @Test func downloadStatesKnowWhenTheyCanStart() {
        #expect(ModelDownloadState.notInstalled.canStart && ModelDownloadState.failed("x").canStart)
        #expect(!ModelDownloadState.installed.canStart && !ModelDownloadState.verifying.canStart)
        #expect(ModelDownloadState.failed("x").isFailed && !ModelDownloadState.installed.isFailed)
    }
}
