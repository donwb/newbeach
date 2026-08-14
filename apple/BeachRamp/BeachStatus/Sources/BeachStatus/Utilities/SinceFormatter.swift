import Foundation

/// Formats the time a status took effect relative to "now", matching the
/// server's TRMNL formatting so copy is identical across platforms:
/// a clock time for today ("6:02 AM"), "Yest 4:11 PM" for yesterday,
/// "Jun 8" for anything older.
public enum SinceFormatter {
    /// US Eastern — the timezone all board copy is rendered in.
    public static let eastern = TimeZone(identifier: "America/New_York")!

    public static func string(from date: Date, now: Date = Date(),
                              timeZone: TimeZone = eastern) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        if calendar.isDate(date, inSameDayAs: now) {
            return clock(date, timeZone: timeZone)
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yest " + clock(date, timeZone: timeZone)
        }
        return monthDay(date, timeZone: timeZone)
    }

    /// "3:04 PM" — no leading zero on the hour.
    public static func clock(_ date: Date, timeZone: TimeZone = eastern) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    /// "Jun 8"
    private static func monthDay(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}
