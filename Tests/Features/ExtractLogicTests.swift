import Foundation
import Testing
@testable import AnyRouter

struct ExtractLogicTests {
    private let receipt = FieldSpec("Merchant")
    private let total = FieldSpec("Total", .money)

    // MARK: presets

    @Test func theFivePresetsAreInOrderAndOnlyCustomStartsEmpty() {
        #expect(ExtractLogic.presets.map(\.id) == ["receipt", "bill", "invoice", "email", "custom"])
        for preset in ExtractLogic.presets where !preset.isCustom {
            #expect(!preset.fields.isEmpty)
            #expect(Set(preset.fields.map(\.name)).count == preset.fields.count)
        }
        #expect(ExtractLogic.preset(id: "custom")?.fields.isEmpty == true)
        #expect(ExtractLogic.preset(id: "custom")?.isCustom == true)
        #expect(ExtractLogic.preset(id: "receipt")?.isCustom == false)
        #expect(ExtractLogic.preset(id: "nope") == nil)
    }

    @Test func kindsDescribeThemselvesForTheUserAndThePrompt() {
        #expect(FieldSpec.Kind.allCases.map(\.title) == ["Text", "Number", "Date", "Money"])
        #expect(FieldSpec.Kind.allCases.map(\.instruction) == [
            "text", "a number", "a date written as YYYY-MM-DD", "an amount with its currency",
        ])
        #expect(FieldSpec("Total", .money).id == "Total")
    }

    @Test func addingAFieldTrimsItAndIgnoresBlankAndRepeatedNames() {
        var fields = ExtractLogic.adding(FieldSpec("  Tip ", .money, hint: "gratuity"), to: [])
        #expect(fields == [FieldSpec("Tip", .money, hint: "gratuity")])
        fields = ExtractLogic.adding(FieldSpec("tip"), to: fields)
        fields = ExtractLogic.adding(FieldSpec("   "), to: fields)
        #expect(fields.count == 1)
        fields = ExtractLogic.adding(FieldSpec("Server"), to: fields)
        #expect(fields.map(\.name) == ["Tip", "Server"])
    }

    @Test func extractNeedsTextAndAtLeastOneField() {
        #expect(ExtractLogic.canExtract(text: "a", fields: [receipt]))
        #expect(!ExtractLogic.canExtract(text: " \n", fields: [receipt]))
        #expect(!ExtractLogic.canExtract(text: "a", fields: []))
    }

    // MARK: text sent to the model

    @Test func aPhoneModelGetsLessOfTheDocumentThanTheCloud() {
        #expect(ExtractLogic.characterLimit(for: .apple) == 6_000)
        #expect(ExtractLogic.characterLimit(for: .gguf) == 6_000)
        #expect(ExtractLogic.characterLimit(for: .mlx) == 6_000)
        #expect(ExtractLogic.characterLimit(for: .anyrouter) == 40_000)
    }

    @Test func clippingKeepsThePrefixAndSaysWhenItCut() {
        #expect(ExtractLogic.clipped("abcdef", limit: 6) == ("abcdef", false))
        #expect(ExtractLogic.clipped("abcdefg", limit: 6) == ("abcdef", true))
        #expect(ExtractLogic.cutNote(limit: 6, total: 7) == "Only the first 6 of 7 characters are sent to this model.")
    }

    // MARK: prompt

    @Test func thePromptListsEveryFieldWithItsKindAndHintThenTheDocument() {
        let prompt = ExtractLogic.prompt(
            fields: [receipt, FieldSpec("Date", .date, hint: "printed top right"), FieldSpec("Tip", .money, hint: "")],
            text: "CAFE 12\nTotal 5.00")
        #expect(prompt.contains("- Merchant (text)\n"))
        #expect(prompt.contains("- Date (a date written as YYYY-MM-DD): printed top right\n"))
        #expect(prompt.contains("- Tip (an amount with its currency)\n"))
        #expect(prompt.contains(##"[{"name": "<field name>", "value": "<the value>", "quote": "<the words in the document it came from>"}]"##))
        #expect(prompt.contains("copy each quote exactly"))
        #expect(prompt.hasSuffix("Document:\nCAFE 12\nTotal 5.00"))
    }

    // MARK: reply

    private func parse(_ reply: String, _ fields: [FieldSpec]? = nil, text: String = "CAFE 12\nTotal 5.00") throws -> [ExtractedField] {
        try ExtractLogic.parse(reply, fields: fields ?? [receipt, total], in: text)
    }

    @Test func aPlainReplyGivesEachFieldItsValueQuoteAndSource() throws {
        let fields = try parse(##"[{"name":"Merchant","value":"Cafe 12","quote":"CAFE 12"},{"name":"Total","value":"5.00","quote":"Total 5.00"}]"##)
        #expect(fields == [
            ExtractedField(name: "Merchant", kind: .text, value: "Cafe 12", quote: "CAFE 12", source: 0..<7),
            ExtractedField(name: "Total", kind: .money, value: "5.00", quote: "Total 5.00", source: 8..<18),
        ])
    }

    @Test func fencesAndProseAroundTheArrayAreIgnored() throws {
        let reply = "Sure! Here you go:\n```json\n[{\"name\":\"Merchant\",\"value\":\"Cafe\",\"quote\":\"CAFE\"}]\n```\nAnything else?"
        let fields = try parse(reply, [receipt])
        #expect(fields.first?.value == "Cafe")
        #expect(fields.first?.source == 0..<4)
    }

    @Test func aBracketInTheProseBeforeTheArrayIsSkipped() throws {
        let reply = ##"See [1] and [x. Result: [{"name":"Merchant","value":"Cafe","quote":"CAFE"}]"##
        #expect(try parse(reply, [receipt]).first?.value == "Cafe")
    }

    @Test func bracketsAndEscapedQuotesInsideStringsDoNotEndTheArray() throws {
        let reply = ##"[{"name":"Merchant","value":"Cafe [12] \"Big\"","quote":"a \\ b ] c"}]"##
        let field = try #require(try parse(reply, [receipt], text: "x").first)
        #expect(field.value == ##"Cafe [12] "Big""##)
        #expect(field.quote == ##"a \ b ] c"##)
        #expect(field.source == nil)
    }

    @Test func numbersAndNullAreReadAsValues() throws {
        let reply = ##"[{"name":"A","value":12,"quote":"q"},{"name":"B","value":4.5,"quote":null},{"name":"C","value":null},{"name":"D","value":true}]"##
        let fields = try parse(reply, ["A", "B", "C", "D"].map { FieldSpec($0) })
        #expect(fields.map(\.value) == ["12", "4.5", "", ""])
        #expect(fields.map(\.quote) == ["q", "", "", ""])
    }

    @Test func namesMatchWithoutCaseAndTheFirstEntryWinsAndStrangersAreIgnored() throws {
        let reply = ##"[{"name":" merchant ","value":"One","quote":"CAFE"},{"name":"Merchant","value":"Two"},{"name":"Other","value":"x"}]"##
        let fields = try parse(reply, [receipt, total])
        #expect(fields.map(\.value) == ["One", ""])
        #expect(fields.map(\.name) == ["Merchant", "Total"])
    }

    @Test func aQuoteThatIsNotInTheTextHasNoSource() throws {
        let fields = try parse(##"[{"name":"Merchant","value":"Cafe","quote":"SHOP 99"}]"##, [receipt])
        #expect(fields.first?.source == nil)
        #expect(fields.first.flatMap(ExtractLogic.note(for:)) == "Not found in the text")
    }

    @Test func anEmptyArrayLeavesEveryFieldEmpty() throws {
        let fields = try parse("[]")
        #expect(fields.allSatisfy { $0.value.isEmpty && $0.quote.isEmpty && $0.source == nil })
    }

    @Test func aReplyWithoutAReadableArrayThrows() {
        for reply in ["", "no json here", "[ unclosed", "[1, 2]", ##"{"name":"Merchant"}"##, ##"[{"value":"x"}]"##] {
            #expect(throws: ExtractError.unreadable) { try parse(reply) }
        }
        #expect(ExtractError.unreadable.errorDescription?.contains("could not be read") == true)
        #expect(ExtractError.noText.errorDescription == "There is no text to extract from.")
    }

    // MARK: locate

    @Test func anExactQuoteGivesItsOffsets() {
        #expect(ExtractLogic.locate("B", in: "A B") == 2..<3)
        #expect(ExtractLogic.locate("  Total 5.00 \n", in: "CAFE 12\nTotal 5.00") == 8..<18)
    }

    @Test func aQuoteMatchesIgnoringCaseAndWhitespaceAndKeepsOriginalOffsets() {
        let text = "Total:\n  USD   42.10 \nThanks"
        #expect(ExtractLogic.locate("usd 42.10", in: text) == 9..<20)
        #expect(ExtractLogic.locate("total: usd", in: text) == 0..<12)
        #expect(ExtractLogic.locate("42.10 thanks", in: text) == 15..<28)
        #expect(ExtractLogic.locate("two words", in: "  \n Two\n\n\tWords") == 4..<15)
    }

    @Test func offsetsCountCharactersSoVietnameseTextKeepsItsPlace() {
        let text = "Cửa hàng An\nTổng cộng: 120.000đ"
        let range = ExtractLogic.locate("tổng cộng: 120.000đ", in: text)
        #expect(range == 12..<31)
        let found = range.flatMap { ExtractLogic.stringRange($0, in: text) }
        #expect(found.map { String(text[$0]) } == "Tổng cộng: 120.000đ")
    }

    @Test func nothingIsFoundForEmptyMissingOrTooLongQuotes() {
        #expect(ExtractLogic.locate("", in: "abc") == nil)
        #expect(ExtractLogic.locate(" \n ", in: "abc") == nil)
        #expect(ExtractLogic.locate("zzz", in: "abc") == nil)
        #expect(ExtractLogic.locate("abcd", in: "abc") == nil)
        #expect(ExtractLogic.locate("abc", in: "") == nil)
        #expect(ExtractLogic.locate("ABCD", in: "abc") == nil)
    }

    // MARK: showing the source

    @Test func linesKnowWhereTheyStartEvenWithBlankLinesAndWindowsEndings() {
        let lines = ExtractLogic.lines(of: "ab\r\n\ncde")
        #expect(lines == [DocumentLine(id: 0, start: 0, text: "ab"), DocumentLine(id: 1, start: 3, text: ""),
                          DocumentLine(id: 2, start: 4, text: "cde")])
        #expect(lines.map(\.end) == [2, 3, 7])
        #expect(ExtractLogic.lines(of: "").count == 1)
    }

    @Test func aSourceScrollsToTheLineItStartsOn() {
        let lines = ExtractLogic.lines(of: "ab\ncde\nf")
        #expect(ExtractLogic.lineID(containing: 0, in: lines) == 0)
        #expect(ExtractLogic.lineID(containing: 4, in: lines) == 1)
        #expect(ExtractLogic.lineID(containing: 8, in: lines) == 2)
        #expect(ExtractLogic.lineID(containing: -1, in: lines) == nil)
    }

    @Test func aRangeThatSpansLinesIsCutToEachLine() {
        let lines = ExtractLogic.lines(of: "ab\ncde\nf")
        let ranges = [1..<5, 7..<8]
        #expect(ExtractLogic.localRanges(ranges, in: lines[0]) == [1..<2])
        #expect(ExtractLogic.localRanges(ranges, in: lines[1]) == [0..<2])
        #expect(ExtractLogic.localRanges(ranges, in: lines[2]) == [0..<1])
        #expect(ExtractLogic.localRanges([5..<6], in: lines[0]).isEmpty)
    }

    @Test func aStringRangeMustFitTheText() {
        #expect(ExtractLogic.stringRange(-1..<2, in: "abc") == nil)
        #expect(ExtractLogic.stringRange(1..<4, in: "abc") == nil)
        let range = ExtractLogic.stringRange(1..<3, in: "abc")
        #expect(range.map { String("abc"[$0]) } == "bc")
    }

    // MARK: results

    @Test func aRowSaysWhyItHasNoSourceAndNothingWhenItHasOne() {
        func field(_ value: String, _ source: Range<Int>?) -> ExtractedField {
            ExtractedField(name: "n", kind: .text, value: value, quote: "q", source: source)
        }
        #expect(ExtractLogic.note(for: field("", nil)) == "No value in the text")
        #expect(ExtractLogic.note(for: field("v", nil)) == "Not found in the text")
        #expect(ExtractLogic.note(for: field("v", 0..<1)) == nil)
    }

    @Test func exportedTextHasOneLinePerFilledField() {
        let fields = [
            ExtractedField(name: "Merchant", kind: .text, value: "Cafe", quote: "", source: nil),
            ExtractedField(name: "Tip", kind: .money, value: "", quote: "", source: nil),
            ExtractedField(name: "Total", kind: .money, value: "5.00", quote: "", source: nil),
        ]
        #expect(ExtractLogic.exported(fields) == "Merchant: Cafe\nTotal: 5.00")
    }
}
