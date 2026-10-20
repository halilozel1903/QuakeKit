import Foundation

/// Times as the USGS APIs read and write them.
public enum QuakeTime {
    /// A date as the FDSN event service reads it: ISO 8601 in UTC without a zone designator,
    /// such as `2026-10-01T06:30:00`.
    public static func queryString(_ date: Date) -> String {
        let calendar = utcCalendar
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(
            format: "%04d-%02d-%02dT%02d:%02d:%02d",
            parts.year ?? 1970, parts.month ?? 1, parts.day ?? 1,
            parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0
        )
    }

    /// Milliseconds since 1970, as `time` and `updated` are sent.
    public static func milliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }

    /// A date from milliseconds since 1970.
    public static func date(milliseconds: Int64) -> Date {
        Date(timeIntervalSince1970: Double(milliseconds) / 1000)
    }

    static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}
