import Foundation

/// The clock and calendar, which a model cannot know.
struct CurrentDateTimeTool: BuiltInTool {
    let name = "current_date_time"
    let title = "Date and time"
    let summary = "The current date, time and time zone"
    let description = "Get the current date and time. Optionally pass an IANA time zone such as Asia/Tokyo; the default is the device's time zone."
    let inputSchemaJSON = #"{"type":"object","properties":{"timezone":{"type":"string","description":"IANA time zone id, for example Europe/Paris"}}}"#

    var now: @Sendable () -> Date = { Date() }
    var deviceTimeZone: @Sendable () -> TimeZone = { .current }

    func run(_ arguments: JSONValue) async throws -> String {
        var zone = deviceTimeZone()
        if let id = arguments["timezone"]?.string, !id.isEmpty {
            guard let requested = TimeZone(identifier: id) else { throw BuiltInToolError("Unknown time zone: \(id).") }
            zone = requested
        }
        let date = now()
        let iso = ISO8601DateFormatter()
        iso.timeZone = zone
        iso.formatOptions = [.withInternetDateTime]
        let weekday = DateFormatter()
        weekday.locale = Locale(identifier: "en_US_POSIX")
        weekday.timeZone = zone
        weekday.dateFormat = "EEEE"
        return "\(iso.string(from: date)) (\(zone.identifier)), \(weekday.string(from: date))"
    }
}
