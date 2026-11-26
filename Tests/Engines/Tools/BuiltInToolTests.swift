import XCTest

@testable import AnyRouter

final class CalculatorTests: XCTestCase {
    private func eval(_ text: String) throws -> String { Calculator.format(try Calculator.evaluate(text)) }

    func testPrecedenceParenthesesAndPowers() throws {
        XCTAssertEqual(try eval("1 + 2 * 3"), "7")
        XCTAssertEqual(try eval("(1 + 2) * 3"), "9")
        XCTAssertEqual(try eval("2 ^ 3 ^ 2"), "512", "power is right associative")
        XCTAssertEqual(try eval("-2 ^ 2"), "-4")
        XCTAssertEqual(try eval("10 % 4 + 7 / 2"), "5.5")
        XCTAssertEqual(try eval("--3"), "3")
    }

    func testFunctionsAndConstants() throws {
        XCTAssertEqual(try eval("sqrt(144) + abs(-3)"), "15")
        XCTAssertEqual(try eval("round(2.5) + floor(2.9) + ceil(2.1)"), "8")
        XCTAssertEqual(try eval("ln(e)"), "1")
        XCTAssertEqual(try eval("2 * pi").prefix(6), "6.2831")
    }

    func testDecimalsKeepTheirDigits() throws {
        XCTAssertEqual(try eval("0.1 + 0.2"), "0.3")
        XCTAssertEqual(try eval("1 / 3"), "0.333333333333")
    }

    func testBadInputIsAReadableError() {
        let cases: [(String, String)] = [
            ("1 / 0", "Division by zero."),
            ("5 % 0", "Division by zero."),
            ("(1 + 2", "Missing a closing parenthesis."),
            ("1 +", "The expression ends too early."),
            ("2 $ 3", "Unexpected \"$\" in the expression."),
            ("1 2", "Unexpected \"2\" in the expression."),
            ("foo + 1", "Unknown name: foo."),
            ("foo(1)", "Unknown function: foo."),
            ("sqrt(-1)", "The square root of a negative number is not real."),
            ("ln(0)", "The logarithm needs a positive number."),
            ("1..2", "Not a number: 1..2."),
            ("10 ^ 1000", "The result is not a finite number."),
        ]
        for (input, message) in cases {
            XCTAssertThrowsError(try Calculator.evaluate(input), input) { error in
                XCTAssertEqual((error as? BuiltInToolError)?.message, message, input)
            }
        }
    }

    func testHostileInputCannotOverflowTheStack() {
        let deep = String(repeating: "(", count: 400) + "1" + String(repeating: ")", count: 400)
        XCTAssertThrowsError(try Calculator.evaluate(deep))
        XCTAssertThrowsError(try Calculator.evaluate(String(repeating: "1+", count: 400) + "1"))
    }

    func testToolReadsTheExpressionArgument() async throws {
        let tool = CalculatorTool()
        let answer = try await tool.run(.object(["expression": .string("2 + 2")]))
        XCTAssertEqual(answer, "4")
        do {
            _ = try await tool.run(.object([:]))
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual((error as? BuiltInToolError)?.message, "Missing the \"expression\" argument.")
        }
    }
}

final class CurrentDateTimeTests: XCTestCase {
    private func tool() -> CurrentDateTimeTool {
        var tool = CurrentDateTimeTool()
        tool.now = { Date(timeIntervalSince1970: 1_800_000_000) }  // 2027-01-15 08:00:00 UTC
        tool.deviceTimeZone = { TimeZone(identifier: "GMT")! }
        return tool
    }

    func testDefaultsToTheDeviceTimeZoneAsOnePlainSentence() async throws {
        let answer = try await tool().run(.object([:]))
        XCTAssertEqual(answer, "Current local time: 08:00, Friday 15 January 2027 (UTC).")
    }

    func testAskedTimeZoneChangesTheOffsetAndTheDay() async throws {
        let answer = try await tool().run(.object(["timezone": .string("Pacific/Kiritimati")]))
        XCTAssertEqual(answer, "Current time in Pacific/Kiritimati: 22:00, Friday 15 January 2027 (UTC+14).")
    }

    /// The bug: the device zone id went to the on-device model, which then talked about a city.
    func testTheDeviceZoneIsNeverNamedSoTheModelHasNoPlaceToTalkAbout() async throws {
        for id in ["Asia/Ho_Chi_Minh", "Europe/Paris", "America/Argentina/Buenos_Aires", "Asia/Kolkata"] {
            var tool = tool()
            tool.deviceTimeZone = { TimeZone(identifier: id)! }
            let answer = try await tool.run(.object([:]))
            XCTAssertFalse(answer.contains("/"), answer)
            XCTAssertFalse(answer.contains("_"), answer)
            XCTAssertTrue(answer.hasPrefix("Current local time: "), answer)
        }
        var vietnam = tool()
        vietnam.deviceTimeZone = { TimeZone(identifier: "Asia/Ho_Chi_Minh")! }
        let answer = try await vietnam.run(.object([:]))
        XCTAssertEqual(answer, "Current local time: 15:00, Friday 15 January 2027 (UTC+7).")
    }

    func testHalfHourAndNegativeOffsets() {
        XCTAssertEqual(CurrentDateTimeTool.offsetText(0), "UTC")
        XCTAssertEqual(CurrentDateTimeTool.offsetText(7 * 3600), "UTC+7")
        XCTAssertEqual(CurrentDateTimeTool.offsetText(19_800), "UTC+5:30")
        XCTAssertEqual(CurrentDateTimeTool.offsetText(-12_600), "UTC-3:30")
        XCTAssertEqual(CurrentDateTimeTool.offsetText(-5 * 3600), "UTC-5")
    }

    func testTheDescriptionDoesNotInviteAPlace() {
        let tool = CurrentDateTimeTool()
        XCTAssertFalse(tool.description.contains("Asia"))
        XCTAssertTrue(tool.inputSchemaJSON.contains("Leave out unless the user asks"))
    }

    func testUnknownTimeZoneIsAnError() async {
        do {
            _ = try await tool().run(.object(["timezone": .string("Mars/Base")]))
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual((error as? BuiltInToolError)?.message, "Unknown time zone: Mars/Base.")
        }
    }
}

final class HTMLTextTests: XCTestCase {
    func testScriptsStylesAndTagsAreDroppedAndBlocksBecomeLines() {
        let html = """
            <html><head><title>Hello &amp; welcome</title><style>p{color:red}</style></head>
            <body><script>alert(1)</script><h1>Head</h1><p>One <b>bold</b>   word.</p><p>Two&nbsp;&lt;3&#33;</p>
            <!-- hidden --><ul><li>a</li><li>b</li></ul></body></html>
            """
        XCTAssertEqual(HTMLText.title(in: html), "Hello & welcome")
        // Blocks keep a blank line between them; what matters is the text and its order.
        let lines = HTMLText.readable(html).components(separatedBy: "\n").filter { !$0.isEmpty }
        XCTAssertEqual(lines, ["Head", "One bold word.", "Two <3!", "a", "b"])
    }

    func testEntities() {
        XCTAssertEqual(HTMLText.decode("a &amp; b &#x41; &#66; &unknown; &"), "a & b A B &unknown; &")
        XCTAssertEqual(HTMLText.decode("no entities"), "no entities")
        XCTAssertEqual(HTMLText.decode("&#99999999999;"), "&#99999999999;")
    }

    func testPageWithoutATitle() {
        XCTAssertNil(HTMLText.title(in: "<p>x</p>"))
        XCTAssertNil(HTMLText.title(in: "<title>  </title>"))
    }
}

final class DeadlineTests: XCTestCase {
    func testFastWorkReturnsItsValue() async throws {
        let value = try await withDeadline(5) { 42 }
        XCTAssertEqual(value, 42)
    }

    func testSlowWorkIsStoppedAndCancelled() async {
        let cancelled = Flag()
        do {
            _ = try await withDeadline(0.05) { () -> Int in
                do { try await Task.sleep(for: .seconds(30)) } catch { cancelled.value = true; throw error }
                return 1
            }
            XCTFail("expected a timeout")
        } catch {
            XCTAssertEqual(error as? DeadlineError, DeadlineError(seconds: 0.05))
            XCTAssertEqual(error.localizedDescription, "The tool took longer than 0.05 seconds and was stopped.")
        }
        let stopped = await waitUntilAsync { cancelled.value }
        XCTAssertTrue(stopped)
    }

    func testClippedTextSaysWhenItCutsTheText() {
        XCTAssertEqual(clippedText("abc", limit: 5), "abc")
        XCTAssertEqual(clippedText("abcdef", limit: 3), "abc\n[Cut at 3 characters.]")
    }
}

/// Polls from a non-main context.
func waitUntilAsync(_ condition: @Sendable () -> Bool) async -> Bool {
    for _ in 0..<300 {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}
