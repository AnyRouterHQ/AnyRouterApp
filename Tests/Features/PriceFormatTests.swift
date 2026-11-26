import Foundation
import Testing
@testable import AnyRouter

struct PriceFormatTests {
    @Test func pricesAreCompact() {
        #expect(PriceFormat.amount(3) == "$3")
        #expect(PriceFormat.amount(15) == "$15")
        #expect(PriceFormat.amount(Decimal(string: "0.15")!) == "$0.15")
        #expect(PriceFormat.amount(Decimal(string: "1.25")!) == "$1.25")
        #expect(PriceFormat.amount(Decimal(string: "0.075")!) == "$0.075")
        #expect(PriceFormat.amount(Decimal(string: "2.50")!) == "$2.5")
    }

    @Test func lineIsFreeOrInAndOutPerMillion() {
        let paid = CloudPricing(input: 3, output: 15, cacheRead: nil, billing: .credits)
        #expect(PriceFormat.line(paid) == "$3 / $15 per 1M")
        #expect(PriceFormat.line(CloudPricing(input: 0, output: 0, cacheRead: nil, billing: .free)) == "Free")
        // Zero price counts as free even when the billing label is something else.
        #expect(PriceFormat.line(CloudPricing(input: 0, output: 0, cacheRead: nil, billing: .credits)) == "Free")
        #expect(PriceFormat.line(CloudPricing(input: nil, output: nil, cacheRead: nil, billing: .byok)) == "Your key")
        #expect(PriceFormat.line(CloudPricing(input: nil, output: nil, cacheRead: nil, billing: .credits)) == nil)
    }

    @Test func contextReadsNaturallyForPowersOfTwoAndRoundNumbers() {
        #expect(PriceFormat.context(1_000_000) == "1M ctx")
        #expect(PriceFormat.context(1_048_576) == "1M ctx")
        #expect(PriceFormat.context(4_194_304) == "4M ctx")
        #expect(PriceFormat.context(128_000) == "128K ctx")
        #expect(PriceFormat.context(131_072) == "128K ctx")
        #expect(PriceFormat.context(200_000) == "200K ctx")
        #expect(PriceFormat.context(512) == "512 ctx")
        #expect(PriceFormat.context(8192) == "8K ctx")
        #expect(PriceFormat.context(32_768) == "32K ctx")
        #expect(PriceFormat.context(196_608) == "192K ctx")
    }

    @Test func requestCostKeepsSmallAmountsVisible() {
        #expect(PriceFormat.cost(0) == "Free")
        #expect(PriceFormat.cost(Decimal(string: "0.0004")!) == "$0.0004")
        #expect(PriceFormat.cost(Decimal(string: "0.25")!) == "$0.25")
    }
}
