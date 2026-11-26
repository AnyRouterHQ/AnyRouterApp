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
        #expect(PriceFormat.cost(0) == "$0")
        #expect(PriceFormat.cost(Decimal(string: "0.0004")!) == "$0.0004")
        #expect(PriceFormat.cost(Decimal(string: "0.25")!) == "$0.25")
    }

    @Test func countsAreCompactWithOneDecimalAtMost() {
        #expect(PriceFormat.compactCount(0) == "0")
        #expect(PriceFormat.compactCount(999) == "999")
        #expect(PriceFormat.compactCount(1000) == "1K")
        #expect(PriceFormat.compactCount(12_307) == "12.3K")
        #expect(PriceFormat.compactCount(53_975) == "54K")
        #expect(PriceFormat.compactCount(2_113_584) == "2.1M")
        #expect(PriceFormat.compactCount(1_200_000_000) == "1.2B")
        #expect(PriceFormat.compactCount(12_345_678_901) == "12.3B")
    }

    @Test func countsRoundUpIntoTheNextUnitInsteadOfShowingFourDigits() {
        #expect(PriceFormat.compactCount(999_949) == "999.9K")
        #expect(PriceFormat.compactCount(999_950) == "1M")
        #expect(PriceFormat.compactCount(999_949_999) == "999.9M")
        #expect(PriceFormat.compactCount(999_950_000) == "1B")
    }

    @Test func groupedNumbersUseCommas() {
        #expect(PriceFormat.grouped(0) == "0")
        #expect(PriceFormat.grouped(999) == "999")
        #expect(PriceFormat.grouped(128_000) == "128,000")
        #expect(PriceFormat.grouped(1_050_000) == "1,050,000")
    }
}
