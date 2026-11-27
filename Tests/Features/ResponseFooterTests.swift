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

    private func value(_ label: String, in metadata: ResponseMetadata) -> String? {
        ResponseFormat.expanded(metadata).first { $0.label == label }?.value
    }

    @Test func aZeroCostReadsAsZeroDollarsNotFree() {
        #expect(value("Cost", in: metadata(cost: 0)) == "$0")
        #expect(PriceFormat.cost(0) == "$0")
    }

    @Test func smallAndNormalCostsKeepTheirDigits() {
        #expect(value("Cost", in: metadata(cost: Decimal(string: "0.0004")!)) == "$0.0004")
        #expect(value("Cost", in: metadata(cost: Decimal(string: "0.25")!)) == "$0.25")
    }

    @Test func anUnknownCostShowsNothing() {
        #expect(value("Cost", in: metadata(cost: nil)) == nil)
    }

    @Test func theFirstTokenTimeIsOnTheRowNotInTheDetails() {
        #expect(value("First token", in: metadata(ttft: 400)) == nil)
    }

    @Test func theDetailsOpenWithCostThenTotalSpeedAndTokens() {
        var full = metadata(cost: 0, ttft: 400, total: 3200, prompt: 12, completion: 80)
        full.servedModelID = "apple/foundation"
        full.provider = "On device"
        full.requestID = "req_1"
        let labels = ResponseFormat.expanded(full).map(\.label)
        #expect(labels == ["Model", "Provider", "Cost", "Total", "Speed", "Tokens", "Request"])
        #expect(value("Total", in: full) == "3.2s")
        #expect(value("Tokens", in: full) == "12 in / 80 out")
    }

    @Test func missingValuesAreLeftOutOfTheDetails() {
        #expect(ResponseFormat.expanded(metadata()).isEmpty)
        #expect(ResponseFormat.expanded(metadata(total: 900)).map(\.label) == ["Total"])
    }
}
