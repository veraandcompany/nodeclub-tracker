import Foundation

/// Daily usage rollup ("yyyy-MM-dd" -> usage), persisted across launches.
///
/// The live session scan is the source of truth for days that still have
/// session files; this file is a backfill so charts survive deleted sessions.
public struct PiUsageHistory: Codable, Sendable, Equatable {
    public var days: [String: PiUsage]

    public init(days: [String: PiUsage] = [:]) {
        self.days = days
    }
}

/// Deterministic day keys: "2026-09-16" (local calendar day).
public enum PiDayKey {
    public static func string(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}

/// Loads/saves the history file. Missing or corrupt files yield empty history.
public enum PiHistoryStore {
    /// `~/.nodeclub-tracker/history.json`, overridable via `PI_HISTORY_FILE`.
    public static var defaultFileURL: URL {
        if let override = ProcessInfo.processInfo.environment["PI_HISTORY_FILE"] {
            return URL(fileURLWithPath: override)
        }
        return URL(fileURLWithPath: NSHomeDirectory() + "/.nodeclub-tracker/history.json")
    }

    public static func load(url: URL = defaultFileURL) -> PiUsageHistory {
        guard
            let data = try? Data(contentsOf: url),
            let history = try? JSONDecoder().decode(PiUsageHistory.self, from: data)
        else { return PiUsageHistory() }
        return history
    }

    public static func save(_ history: PiUsageHistory, to url: URL = defaultFileURL) {
        guard let data = try? JSONEncoder().encode(history) else { return }
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}

/// One bar of the history chart.
public struct PiDayPoint: Identifiable, Sendable, Equatable {
    public var id: String { key }
    public var key: String
    public var label: String
    public var usage: PiUsage

    public init(key: String, label: String, usage: PiUsage) {
        self.key = key
        self.label = label
        self.usage = usage
    }
}

/// Usage window selectable in the popover.
public enum PiUsagePeriod: String, CaseIterable, Identifiable, Sendable {
    case day = "Today"
    case month = "Month"
    case year = "Year"

    public var id: String { rawValue }
}

/// Pure history math: charts, windows, and the live/persisted merge.
public enum PiHistorySummary {
    /// Last `length` days old-to-new, zero-filled for days without data.
    public static func series(
        days: [String: PiUsage],
        length: Int,
        now: Date,
        calendar: Calendar
    ) -> [PiDayPoint] {
        var points: [PiDayPoint] = []
        points.reserveCapacity(length)
        let startOfDay = calendar.startOfDay(for: now)
        for offset in stride(from: length - 1, through: 0, by: -1) {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: startOfDay) else { continue }
            let components = calendar.dateComponents([.month, .day], from: date)
            points.append(PiDayPoint(
                key: PiDayKey.string(for: date, calendar: calendar),
                label: "\(components.month ?? 0)/\(components.day ?? 0)",
                usage: days[PiDayKey.string(for: date, calendar: calendar)] ?? .zero
            ))
        }
        return points
    }

    /// Summed usage over the last `length` days (including today).
    public static func window(
        days: [String: PiUsage],
        length: Int,
        now: Date,
        calendar: Calendar
    ) -> PiUsage {
        series(days: days, length: length, now: now, calendar: calendar)
            .reduce(.zero) { $0 + $1.usage }
    }

    /// Summed usage for the current day/month/year. Day keys are "yyyy-MM-dd",
    /// so month/year scopes are simple prefix filters.
    public static func period(
        _ period: PiUsagePeriod,
        days: [String: PiUsage],
        now: Date,
        calendar: Calendar
    ) -> PiUsage {
        switch period {
        case .day:
            return days[PiDayKey.string(for: now, calendar: calendar)] ?? .zero
        case .month:
            let components = calendar.dateComponents([.year, .month], from: now)
            let prefix = String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
            return days.filter { $0.key.hasPrefix(prefix) }.values.reduce(.zero) { $0 + $1 }
        case .year:
            let components = calendar.dateComponents([.year], from: now)
            let prefix = String(format: "%04d", components.year ?? 0)
            return days.filter { $0.key.hasPrefix(prefix) }.values.reduce(.zero) { $0 + $1 }
        }
    }

    /// Merge the live per-day rollup over persisted history, pruned to the
    /// last `retainedDays` days. Live values win for days present in both.
    public static func merged(
        live: [String: PiUsage],
        with persisted: PiUsageHistory,
        retainedDays: Int,
        now: Date,
        calendar: Calendar
    ) -> PiUsageHistory {
        var days = persisted.days
        for (key, usage) in live where usage != .zero {
            days[key] = usage
        }
        let points = series(days: days, length: retainedDays, now: now, calendar: calendar)
        var pruned: [String: PiUsage] = [:]
        for point in points where point.usage != .zero {
            pruned[point.key] = point.usage
        }
        return PiUsageHistory(days: pruned)
    }
}
