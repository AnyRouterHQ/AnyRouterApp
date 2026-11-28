import Foundation

/// The clock and calendar, which a model cannot know.
///
/// The answer is one plain sentence a small model can repeat: the local time, the weekday and date, and a UTC offset.
/// It never names the device's time zone. An earlier version answered `2026-11-27T00:01:00+07:00 (Asia/Ho_Chi_Minh), Thursday`
/// and the on-device model replied with facts about a city it guessed from the zone id instead of the time.
struct CurrentDateTimeTool: BuiltInTool {
    let name = "current_date_time"
    let title = "Date and time"
    let summary = "The current date, time and time zone"
    let description = "Get the current local date and time on this device. Call it without arguments unless the user names another time zone."
    let schema: JSONSchema = #"{"type":"object","properties":{"timezone":{"type":"string","description":"IANA time zone id. Leave out unless the user asks about another place."}}}"#

    var now: @Sendable () -> Date = { Date() }
    var deviceTimeZone: @Sendable () -> TimeZone = { .current }

    func run(_ arguments: JSONValue) async throws -> String {
        var zone = deviceTimeZone()
        var asked: String?
        if let id = arguments["timezone"]?.string, !id.isEmpty {
            guard let requested = TimeZone(identifier: id) else { throw BuiltInToolError("Unknown time zone: \(id).") }
            zone = requested
            asked = id
        }
        let date = now()
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.timeZone = zone
        format.dateFormat = "HH:mm, EEEE d MMMM yyyy"
        let when = "\(format.string(from: date)) (\(Self.offsetText(zone.secondsFromGMT(for: date))))"
        // The zone id is only repeated when the user asked for that zone.
        return asked.map { "Current time in \($0): \(when)." } ?? "Current local time: \(when)."
    }

    /// `UTC`, `UTC+7`, `UTC+5:30`, `UTC-3:30`.
    static func offsetText(_ seconds: Int) -> String {
        guard seconds != 0 else { return "UTC" }
        let sign = seconds < 0 ? "-" : "+"
        let minutes = abs(seconds) / 60
        let hours = minutes / 60, rest = minutes % 60
        return "UTC\(sign)\(hours)" + (rest == 0 ? "" : ":" + String(format: "%02d", rest))
    }
}
