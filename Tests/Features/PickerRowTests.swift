import Foundation
import Testing
@testable import AnyRouter

/// The text of every kind of picker row: name and id on line one, price or state on line two.
struct PickerRowTests {
    @Test func cloudRowShowsNameIdPriceContextAndUpstreams() {
        let row = PickerRow.make(cloudModel(
            "anthropic/claude-sonnet-4-6", name: "Claude Sonnet 4.6", context: 1_000_000, upstreams: 35,
            vision: true, reasoning: true))
        #expect(row.title == "Claude Sonnet 4.6")
        #expect(row.idLabel == "anthropic/claude-sonnet-4-6")
        #expect(row.details == ["$3 / $15 per 1M", "1M ctx", "35 upstreams", "vision", "reasoning"])
        #expect(!row.isDimmed)
    }

    @Test func freeModelsSaySoAndRoutersCountTheirMembers() {
        let auto = PickerRow.make(cloudModel(
            "anyrouter/auto", name: "AnyRouter Auto", input: 0, output: 0, billing: .free,
            upstreams: 1, members: 7, context: 4_194_304))
        #expect(auto.title == "AnyRouter")
        #expect(auto.idLabel == "anyrouter/auto")
        #expect(auto.details == ["Free", "4M ctx", "routes 7 models"])
    }

    @Test func anUnusableModelShowsTheReasonInsteadOfThePriceAndIsDimmed() {
        let needsKey = PickerRow.make(cloudModel("openai/gpt-5", availability: .needsKey, upstreams: 26))
        #expect(needsKey.details.first == "Needs your provider key")
        #expect(!needsKey.details.contains { $0.contains("per 1M") })
        #expect(needsKey.isDimmed)
        #expect(needsKey.needsKey)
        let gone = PickerRow.make(cloudModel("vendor/old", availability: .noRoute))
        #expect(gone.details.first == "Unavailable")
        #expect(gone.isDimmed)
        #expect(!gone.needsKey)
    }

    @Test func oneUpstreamIsSingular() {
        #expect(PickerRow.make(cloudModel("a/b", upstreams: 1)).details.contains("1 upstream"))
    }

    @Test func localRowShowsOnDeviceSizeFormatAndFit() {
        let row = PickerRow.make(
            localModel("gguf/unsloth/gemma-3-1b-it-GGUF/gemma-3-1b-it-Q4_K_M.gguf", name: "Gemma 3 1B", size: 1_050_000_000),
            fitBadge: "Fits")
        #expect(row.title == "Gemma 3 1B")
        #expect(row.idLabel == PickerRow.middleTruncated("unsloth/gemma-3-1b-it-GGUF/gemma-3-1b-it-Q4_K_M.gguf"))
        #expect(row.idLabel.count <= PickerRow.idLimit)
        #expect(row.details.first == "On device · Free")
        #expect(row.details.contains("GGUF Q4_K_M"))
        #expect(row.details.last == "Fits")
        #expect(row.details.contains { $0.contains("GB") })
    }

    @Test func mlxFormatShowsTheBitWidth() {
        let row = PickerRow.make(localModel("mlx/mlx-community/Qwen3-4B-4bit", source: .mlx, size: 2_300_000_000))
        #expect(row.details.contains("MLX 4-bit"))
    }

    @Test func appleRowIsOnDeviceAndExplainsWhenUnavailable() {
        let ready = PickerRow.make(testModel(id: "apple/foundation", source: .apple))
        #expect(ready.idLabel == "apple/foundation")
        #expect(ready.details == ["On device · Free"])
        var off = testModel(id: "apple/foundation", source: .apple, installed: false)
        off.summary = "Turn on Apple Intelligence in Settings."
        let row = PickerRow.make(off)
        #expect(row.details == ["On device · Free", "Turn on Apple Intelligence in Settings."])
        #expect(row.isDimmed)
    }

    @Test func longIdsKeepBothEnds() {
        let long = "anthropic/claude-sonnet-4-6-extended-thinking-20260101"
        let short = PickerRow.middleTruncated(long)
        #expect(short.count == PickerRow.idLimit)
        #expect(short.hasPrefix("anthropic/claude-sonne"))
        #expect(short.hasSuffix("0101"))
        #expect(short.contains("…"))
        #expect(PickerRow.middleTruncated("openai/gpt-5") == "openai/gpt-5")
    }

    @Test func eachRowHasExactlyTwoLinesOfText() {
        for model in [cloudModel("a/b"), localModel("gguf/o/r/f-Q4_K_M.gguf"), testModel(id: "apple/foundation", source: .apple)] {
            let row = PickerRow.make(model)
            #expect(!row.title.isEmpty)
            #expect(!row.detailLine.contains("\n"))
        }
    }
}
