import Foundation
import Testing
@testable import AnyRouter

/// The text of every kind of picker row: name on line one, price or state on line two.
struct PickerRowTests {
    @Test func cloudRowShowsNamePriceContextAndCapabilitySymbols() {
        let row = PickerRow.make(cloudModel(
            "anthropic/claude-sonnet-4-6", name: "Claude Sonnet 4.6", upstreams: 35, context: 1_000_000,
            vision: true, reasoning: true, tools: true))
        #expect(row.title == "Claude Sonnet 4.6")
        #expect(row.idLabel.isEmpty, "the id is on the detail screen")
        #expect(row.details == ["$3 / $15 per 1M", "1M ctx"], "no upstream count and no capability words on the row")
        #expect(row.capabilities == [.vision, .reasoning, .tools])
        #expect(row.supportsVision)
        #expect(!row.isFree)
        #expect(!row.isDimmed)
    }

    @Test func eachCapabilityHasASymbolAndAnAccessibilityLabel() {
        #expect(RowCapability.allCases.map(\.symbol) == ["eye", "brain", "wrench"])
        #expect(RowCapability.allCases.map(\.title) == ["Sees images", "Reasons step by step", "Uses tools"])
        #expect(RowCapability.allCases.map(\.id) == ["vision", "reasoning", "tools"])
        #expect(PickerRow.make(cloudModel("a/b")).capabilities.isEmpty)
    }

    @Test func aReasoningTagFromTheCatalogShowsTheBrainEvenWithoutAParameter() {
        var model = cloudModel("a/b")
        model.capabilities.insert("reasoning")
        #expect(PickerRow.make(model).capabilities == [.reasoning])
    }

    @Test func freeModelsSaySoAndRoutersCountTheirMembers() {
        let auto = PickerRow.make(cloudModel(
            "anyrouter/auto", name: "AnyRouter Auto", input: 0, output: 0, billing: .free,
            upstreams: 1, members: 7, context: 4_194_304))
        #expect(auto.title == "anyrouter/auto", "a preset shows its full id, not a friendly name")
        #expect(PickerRow.make(cloudModel("openai/gpt-5", name: "GPT-5")).title == "GPT-5")
        #expect(auto.details == ["Free", "4M ctx", "routes 7 models"])
        #expect(auto.isFree)
        #expect(auto.detailsAfterBadge == "4M ctx · routes 7 models")
    }

    @Test func aPaidRowHasNoBadgeSoTheWholeLineIsText() {
        let row = PickerRow.make(cloudModel("a/b", context: 8192))
        #expect(!row.isFree)
        #expect(row.detailsAfterBadge == "$3 / $15 per 1M · 8K ctx")
    }

    @Test func aModelThatNeedsAKeyIsNeverBadgedFree() {
        let row = PickerRow.make(cloudModel("a/b", input: 0, output: 0, billing: .free, availability: .needsKey))
        #expect(!row.isFree)
        #expect(row.details.first == "Needs your provider key")
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

    @Test func weeklyUsageGivesTheTopModelsARankAndEveryModelItsCount() {
        let usage = ModelUsage(id: "a/b", rank: 1, tokens: 1_200_000_000, requests: 53_975)
        let row = PickerRow.make(cloudModel("a/b"), usage: usage)
        #expect(row.rankText == "#1")
        #expect(row.usage?.weeklySummary == "1.2B tokens this week")
        #expect(row.usage?.summary == "1.2B tokens")
        let deep = PickerRow.make(cloudModel("a/b"), usage: ModelUsage(id: "a/b", rank: PickerRow.rankedCount, tokens: 5, requests: 1))
        #expect(deep.rankText == "#\(PickerRow.rankedCount)")
        let far = PickerRow.make(cloudModel("a/b"), usage: ModelUsage(id: "a/b", rank: PickerRow.rankedCount + 1, tokens: 5, requests: 1))
        #expect(far.rankText == nil, "no number past the top list")
        #expect(far.usage?.summary == "5 tokens")
        #expect(PickerRow.make(cloudModel("a/b")).rankText == nil)
    }

    @Test func aWeekWithoutTokensCountsRequestsInstead() {
        #expect(ModelUsage(id: "a", rank: 9, tokens: 0, requests: 34_000).summary == "34K requests")
        #expect(ModelUsage(id: "a", rank: 9, tokens: 0, requests: 1).summary == "1 request")
        #expect(ModelUsage(id: "a", rank: 9, tokens: 1, requests: 1).summary == "1 token")
    }

    @Test func localRowShowsOnDeviceSizeFormatAndFit() {
        let row = PickerRow.make(
            localModel("gguf/unsloth/gemma-3-1b-it-GGUF/gemma-3-1b-it-Q4_K_M.gguf", name: "Gemma 3 1B", size: 1_050_000_000),
            fitBadge: "Fits")
        #expect(row.title == "Gemma 3 1B")
        #expect(row.details.first == "GGUF Q4_K_M", "the variant leads the second line")
        #expect(row.details.contains { $0.contains("GB") })
        #expect(row.details.contains("On device · Free"))
        #expect(row.details.last == "Fits")
        #expect(!row.detailLine.contains("unsloth"), "the repo and file are on the detail screen, not the row")
    }

    @Test func mlxFormatShowsTheBitWidth() {
        let row = PickerRow.make(localModel("mlx/mlx-community/Qwen3-4B-4bit", source: .mlx, size: 2_300_000_000))
        #expect(row.details.contains("MLX 4-bit"))
    }

    @Test func appleRowIsOnDeviceAndExplainsWhenUnavailable() {
        let ready = PickerRow.make(testModel(id: "apple/foundation", source: .apple))
        #expect(ready.details == ["On device · Free"])
        var off = testModel(id: "apple/foundation", source: .apple, installed: false)
        off.summary = "Turn on Apple Intelligence in Settings."
        let row = PickerRow.make(off)
        #expect(row.details == ["On device · Free", "Turn on Apple Intelligence in Settings."])
        #expect(row.isDimmed)
    }

    @Test func aQATRowHasTheShortNameAndItsVariantWithoutNestedBrackets() {
        let row = PickerRow.make(localModel(
            "gguf/google/gemma-4-E2B-it-qat-GGUF/gemma-4-E2B-it-qat-Q4_0.gguf", name: "Gemma 4 E2B (Q4_0 (QAT))",
            size: 3_350_000_000))
        #expect(row.title == "Gemma 4 E2B")
        #expect(row.details.first == "Q4_0 QAT")
        #expect(row.details[2] == "On device · Free")
    }

    @Test func eachRowHasExactlyTwoLinesOfText() {
        for model in [cloudModel("a/b"), localModel("gguf/o/r/f-Q4_K_M.gguf"), testModel(id: "apple/foundation", source: .apple)] {
            let row = PickerRow.make(model)
            #expect(!row.title.isEmpty)
            #expect(!row.detailLine.contains("\n"))
        }
    }
}
