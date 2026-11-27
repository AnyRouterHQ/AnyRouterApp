import Foundation
import Testing
@testable import AnyRouter

struct PasteLogicTests {
    private func base64URL(_ json: String) -> String {
        Data(json.utf8).base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    private func token(header: String = ##"{"alg":"HS256","typ":"JWT"}"##, payload: String) -> String {
        "\(base64URL(header)).\(base64URL(payload)).c2ln"
    }

    @Test func hexAndRGBColorsReadAsBoth() {
        #expect(PasteLogic.detect(" #ff8800 ") == .color(hex: "#FF8800", rgb: "rgb(255, 136, 0)"))
        #expect(PasteLogic.detect("#0af") == .color(hex: "#00AAFF", rgb: "rgb(0, 170, 255)"))
        #expect(PasteLogic.detect("rgb(1, 2,3)") == .color(hex: "#010203", rgb: "rgb(1, 2, 3)"))
        #expect(PasteLogic.detect("rgba(255,255,255,0.5)") == .color(hex: "#FFFFFF", rgb: "rgb(255, 255, 255)"))
        #expect(PasteLogic.detect("rgb(256, 0, 0)") == .text)
        #expect(PasteLogic.detect("ff8800") == .text)
        #expect(PasteLogic.detect("#ff88") == .text)
    }

    @Test func aTokenShowsItsHeaderPayloadAndExpiry() throws {
        let kind = PasteLogic.detect(token(payload: ##"{"sub":"ana","exp":1700000000}"##))
        guard case .jwt(let header, let payload, let expiry) = kind else {
            Issue.record("not a jwt: \(kind)")
            return
        }
        #expect(header.contains("\"alg\" : \"HS256\""))
        #expect(payload.contains("\"sub\" : \"ana\""))
        #expect(expiry == Date(timeIntervalSince1970: 1_700_000_000))
        guard case .jwt(_, _, let none) = PasteLogic.detect(token(payload: ##"{"sub":"ana"}"##)) else {
            Issue.record("not a jwt")
            return
        }
        #expect(none == nil)
    }

    @Test func somethingThatOnlyLooksLikeATokenIsNotOne() {
        #expect(PasteLogic.detect("a.b.c") == .text)
        #expect(PasteLogic.detect("one.two") == .text)
        #expect(PasteLogic.detect(token(header: ##"{"typ":"JWT"}"##, payload: ##"{"a":1}"##)) == .text)
        #expect(PasteLogic.detect("\(base64URL(##"{"alg":"x"}"##)).\(base64URL("[1]")).sig") == .text)
        #expect(PasteLogic.detect("***.\(base64URL("{}")).sig") == .text)
    }

    @Test func jsonIsPrettyPrintedWithSortedKeys() {
        #expect(PasteLogic.detect(##"{"b":1,"a":"x/y"}"##) == .json(pretty: "{\n  \"a\" : \"x/y\",\n  \"b\" : 1\n}"))
        #expect(PasteLogic.detect("[1, 2]") == .json(pretty: "[\n  1,\n  2\n]"))
        #expect(PasteLogic.detect("{broken") == .text)
        #expect(PasteLogic.detect("[") == .text)
    }

    @Test func cronFieldsAndSummaries() {
        func summary(_ text: String) -> String? {
            if case .cron(_, let summary) = PasteLogic.detect(text) { return summary }
            return nil
        }
        #expect(summary("* * * * *") == "Every minute")
        #expect(summary("*/15 * * * *") == "Every 15 minutes")
        #expect(summary("30 9 * * *") == "Every day at 09:30")
        #expect(summary("0 17 * * 5") == "Every Friday at 17:00")
        #expect(summary("0 8 * * 7") == "Every Sunday at 08:00")
        #expect(summary("*/15 9-17 * * 1-5") == "Minute */15, hour 9-17, day *, month *, weekday 1-5")
        #expect(summary("0 8 1 * *") == "Minute 0, hour 8, day 1, month *, weekday *")
        guard case .cron(let fields, _) = PasteLogic.detect("0 8 * * 1") else {
            Issue.record("not cron")
            return
        }
        #expect(fields.map(\.name) == ["Minute", "Hour", "Day of month", "Month", "Day of week"])
        #expect(fields.map(\.value) == ["0", "8", "*", "*", "1"])
    }

    @Test func fiveNumbersOrOutOfRangeFieldsAreNotCron() {
        #expect(PasteLogic.detect("1 2 3 4 5") == .text)
        #expect(PasteLogic.detect("60 * * * *") == .text)
        #expect(PasteLogic.detect("* 24 * * *") == .text)
        #expect(PasteLogic.detect("* * 0 * *") == .text)
        #expect(PasteLogic.detect("* * * 13 *") == .text)
        #expect(PasteLogic.detect("* * * * 8") == .text)
        #expect(PasteLogic.detect("* * * *") == .text)
        #expect(PasteLogic.detect("a b c d *") == .text)
        #expect(PasteLogic.detect("*/x * * * *") == .text)
        #expect(PasteLogic.detect("1,,2 * * * *") == .text)
    }

    @Test func tracesNameTheirLanguageAndKeepTheFrames() {
        let python = "Traceback (most recent call last):\n  File \"app.py\", line 3, in run\n    boom()\n  File \"app.py\", line 9, in boom\nValueError: x"
        #expect(PasteLogic.detect(python) == .stackTrace(language: "Python", frames: ["File \"app.py\", line 3, in run", "File \"app.py\", line 9, in boom"]))
        let java = "java.lang.IllegalStateException: no\n\tat com.acme.Main.run(Main.java:12)\n\tat com.acme.Main.main(Main.java:5)"
        #expect(PasteLogic.detect(java) == .stackTrace(language: "Java", frames: ["at com.acme.Main.run(Main.java:12)", "at com.acme.Main.main(Main.java:5)"]))
        let script = "TypeError: x is not a function\n    at run (/app/index.js:3:9)\n    at /app/index.js:8:1"
        #expect(PasteLogic.detect(script) == .stackTrace(language: "JavaScript", frames: ["at run (/app/index.js:3:9)", "at /app/index.js:8:1"]))
        #expect(PasteLogic.detect("File \"x.py\", line 3") == .text)
        #expect(PasteLogic.detect("Traceback only") == .text)
        #expect(PasteLogic.detect("at com.acme.Main.run(Main.java:12)") == .text)
    }

    @Test func plainTextAndNothingStayText() {
        #expect(PasteLogic.detect("Please send the contract before Friday.") == .text)
        #expect(PasteLogic.detect("  \n ") == .text)
    }

    @Test func eachKindHasATitleAndTheLinesTheCardShows() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(PasteLogic.title(.json(pretty: "")) == "JSON")
        #expect(PasteLogic.title(.jwt(header: "", payload: "", expiry: nil)) == "JWT")
        #expect(PasteLogic.title(.cron(fields: [], summary: "")) == "Cron schedule")
        #expect(PasteLogic.title(.stackTrace(language: "Java", frames: [])) == "Java stack trace")
        #expect(PasteLogic.title(.color(hex: "", rgb: "")) == "Color")
        #expect(PasteLogic.title(.text) == "Text")

        #expect(PasteLogic.rows(.text).isEmpty)
        #expect(PasteLogic.rows(.json(pretty: "{}")).map(\.name) == ["Pretty"])
        #expect(PasteLogic.rows(.color(hex: "#000000", rgb: "rgb(0, 0, 0)")).map(\.value) == ["#000000", "rgb(0, 0, 0)"])
        #expect(PasteLogic.rows(.stackTrace(language: "Java", frames: ["a", "b"])).map(\.value) == ["Java", "a\nb"])
        let cron = PasteLogic.rows(.cron(fields: [PasteField(name: "Minute", value: "0")], summary: "Every minute"))
        #expect(cron.map(\.name) == ["Runs", "Minute"])
        let past = PasteLogic.rows(.jwt(header: "h", payload: "p", expiry: now.addingTimeInterval(-60)), now: now)
        #expect(past.map(\.name) == ["Header", "Payload", "Expiry"] && past[2].value.hasPrefix("Expired 2023-11-14"))
        let future = PasteLogic.rows(.jwt(header: "h", payload: "p", expiry: now.addingTimeInterval(60)), now: now)
        #expect(future[2].value.hasPrefix("Expires 2023-11-14"))
        #expect(PasteLogic.rows(.jwt(header: "h", payload: "p", expiry: nil)).count == 2)
    }
}
