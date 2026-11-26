import Foundation
import Testing
@testable import AnyRouter

struct ResponseFooterTests {
    private func metadata(cost: Decimal? = nil, ttft: Int? = nil, total: Int? = nil,
                          prompt: Int? = nil, completion: Int? = nil) -> ResponseMetadata {
        var value = ResponseMetadata()
        value.costUSD = cost
        value.ttftMs = ttft
        value.totalMs = total
        value.promptTokens = prompt
        value.completionTokens = completion
        return value
    }

    @Test func aZeroCostReadsAsZeroDollarsNotFree() {
        #expect(ResponseFormat.inline(metadata(cost: 0)) == ["$0"])
        #expect(PriceFormat.cost(0) == "$0")
    }

    @Test func smallAndNormalCostsKeepTheirDigits() {
        #expect(ResponseFormat.inline(metadata(cost: Decimal(string: "0.0004")!)) == ["$0.0004"])
        #expect(ResponseFormat.inline(metadata(cost: Decimal(string: "0.25")!)) == ["$0.25"])
    }

    @Test func anUnknownCostShowsNothing() {
        #expect(ResponseFormat.inline(metadata(cost: nil)).isEmpty)
        #expect(ResponseFormat.inline(metadata()).isEmpty)
    }

    @Test func theLineHasOnlyCostAndFirstToken() {
        let line = ResponseFormat.inline(metadata(cost: 0, ttft: 400, total: 3200, prompt: 12, completion: 80))
        #expect(line == ["$0", "first token 0.4s"])
    }

    @Test func totalSpeedAndTokensMoveToTheExpandedDetails() {
        var value = metadata(cost: 0, ttft: 400, total: 3200, prompt: 12, completion: 80)
        value.servedModelID = "apple/foundation"
        value.provider = "On device"
        value.requestID = "req_1"
        let labels = ResponseFormat.expanded(value).map(\.label)
        #expect(labels == ["Model", "Provider", "Total", "Speed", "Tokens", "Request"])
        #expect(ResponseFormat.expanded(value).first { $0.label == "Total" }?.value == "3.2s")
        #expect(ResponseFormat.expanded(value).first { $0.label == "Tokens" }?.value == "12 in / 80 out")
    }

    @Test func expandedDetailsNeverRepeatTheInlineFields() {
        let labels = ResponseFormat.expanded(metadata(cost: 0, ttft: 400, total: 3200)).map(\.label)
        #expect(!labels.contains("Cost"))
        #expect(!labels.contains("First token"))
    }

    @Test func missingValuesAreLeftOutOfTheDetails() {
        #expect(ResponseFormat.expanded(metadata()).isEmpty)
        #expect(ResponseFormat.expanded(metadata(total: 900)).map(\.label) == ["Total"])
    }
}
