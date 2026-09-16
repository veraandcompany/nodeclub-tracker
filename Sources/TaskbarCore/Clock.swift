import Foundation

/// Pure clock formatting. Views call these; tests pin the output.
/// Keep this free of live `Date()` calls so output is deterministic.
public enum ClockText {
    /// "14:30" — compact, for the menu bar label.
    public static func menuBarTime(at date: Date, timeZone: TimeZone = .current) -> String {
        format(date, format: "HH:mm", timeZone: timeZone)
    }

    /// "14:30:05" — precise, for the popover header.
    public static func popoverTime(at date: Date, timeZone: TimeZone = .current) -> String {
        format(date, format: "HH:mm:ss", timeZone: timeZone)
    }

    /// "Monday, June 16" — date line under the popover time.
    public static func longDate(at date: Date, timeZone: TimeZone = .current) -> String {
        format(date, format: "EEEE, MMMM d", timeZone: timeZone, locale: Locale(identifier: "en_US"))
    }

    private static func format(
        _ date: Date,
        format: String,
        timeZone: TimeZone,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        formatter.timeZone = timeZone
        formatter.locale = locale
        return formatter.string(from: date)
    }
}
