import Foundation
import Testing
@testable import AnyRouter

struct VoiceModelLogicTests {
    @Test func theVoiceListHasFourModelsWithDistinctIds() {
        let all = VoiceModelCatalog.all
        #expect(all.map(\.id) == ["kokoro", "soprano", "pocket-tts", "qwen3-tts"])
        #expect(Set(all.map(\.id)).count == all.count)
    }

    @Test func everyVoiceNamesARealRepoASizeAndALicense() {
        for voice in VoiceModelCatalog.all {
            #expect(SettingsLogic.parseRepo(voice.repo) == voice.repo, "\(voice.name) points at a Hugging Face repo id")
            #expect(voice.sizeBytes > 0)
            #expect(!voice.license.isEmpty && !voice.summary.isEmpty)
        }
    }

    @Test func theDetailLineShowsFormatSizeAndLicense() {
        let pocket = VoiceModelCatalog.all[2]
        #expect(pocket.detailLine == "MLX 4-bit · 89 MB · CC-BY-4.0")
        #expect(VoiceModelCatalog.all[0].detailLine == "MLX bf16 · 389 MB · Apache-2.0")
        #expect(VoiceModelCatalog.all[3].detailLine == "MLX 8-bit · 2.0 GB · Apache-2.0")
    }

    @Test func theListIsHonestThatNothingCanBeDownloadedYet() {
        #expect(VoiceModelCatalog.status == "Coming soon")
        #expect(VoiceModelCatalog.footer.contains("none can be downloaded yet"))
    }
}
