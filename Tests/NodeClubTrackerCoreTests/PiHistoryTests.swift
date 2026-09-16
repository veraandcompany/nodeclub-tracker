import Foundation
import NodeClubTrackerCore
import XCTest

final class PiHistoryTests: XCTestCase {
    /// 2026-09-16T12:00:00Z
    private static let now = Date(timeIntervalSince1970: 1_789_560_000)

    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private static func tokens(_ count: Int) -> PiUsage {
        PiUsage(totalTokens: count, turnCount: 1)
    }

    // MARK: - Day keys

    func test_dayKeyFormat() {
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 6
        let date = Self.utcCalendar.date(from: components)!
        XCTAssertEqual(PiDayKey.string(for: date, calendar: Self.utcCalendar), "2026-09-06")
    }

    // MARK: - Series / window

    func test_seriesIsOldToNewAndZeroFilled() {
        let days = ["2026-09-16": Self.tokens(100)]
        let points = PiHistorySummary.series(days: days, length: 3, now: Self.now, calendar: Self.utcCalendar)
        XCTAssertEqual(points.map(\.key), ["2026-09-14", "2026-09-15", "2026-09-16"])
        XCTAssertEqual(points.map(\.label), ["9/14", "9/15", "9/16"])
        XCTAssertEqual(points[0].usage.totalTokens, 0)
        XCTAssertEqual(points[2].usage.totalTokens, 100)
    }

    func test_windowSumsOnlyRecentDays() {
        let days = [
            "2026-09-16": Self.tokens(10),
            "2026-09-10": Self.tokens(20), // exactly 7 days back: inside 7d window
            "2026-09-09": Self.tokens(40), // 8 days back: outside 7d, inside 30d
        ]
        let week = PiHistorySummary.window(days: days, length: 7, now: Self.now, calendar: Self.utcCalendar)
        let month = PiHistorySummary.window(days: days, length: 30, now: Self.now, calendar: Self.utcCalendar)
        XCTAssertEqual(week.totalTokens, 30)
        XCTAssertEqual(month.totalTokens, 70)
    }

    // MARK: - Merge

    func test_mergedLiveWinsAndPrunesOld() {
        let persisted = PiUsageHistory(days: [
            "2026-09-16": Self.tokens(10), // stale live day
            "2026-09-15": Self.tokens(50),
            "2026-07-01": Self.tokens(999), // outside 30d retention
        ])
        let merged = PiHistorySummary.merged(
            live: ["2026-09-16": Self.tokens(100)],
            with: persisted,
            retainedDays: 30,
            now: Self.now,
            calendar: Self.utcCalendar
        )
        XCTAssertEqual(merged.days["2026-09-16"]?.totalTokens, 100)
        XCTAssertEqual(merged.days["2026-09-15"]?.totalTokens, 50)
        XCTAssertNil(merged.days["2026-07-01"])
    }

    func test_mergedDropsZeroDays() {
        let merged = PiHistorySummary.merged(
            live: ["2026-09-16": .zero],
            with: PiUsageHistory(),
            retainedDays: 30,
            now: Self.now,
            calendar: Self.utcCalendar
        )
        XCTAssertTrue(merged.days.isEmpty)
    }

    // MARK: - Store round trip

    func test_storeRoundTrip() throws {
        let file = tempFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let history = PiUsageHistory(days: ["2026-09-16": Self.tokens(42)])
        PiHistoryStore.save(history, to: file)
        let loaded = PiHistoryStore.load(url: file)
        XCTAssertEqual(loaded, history)
    }

    func test_storeMissingFileIsEmpty() {
        let file = tempFile()
        let loaded = PiHistoryStore.load(url: file)
        XCTAssertTrue(loaded.days.isEmpty)
    }

    func test_storeCorruptFileIsEmpty() throws {
        let file = tempFile()
        defer { try? FileManager.default.removeItem(at: file) }
        try "not json".write(to: file, atomically: true, encoding: .utf8)
        let loaded = PiHistoryStore.load(url: file)
        XCTAssertTrue(loaded.days.isEmpty)
    }

    private func tempFile() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("nodeclub-history-\(UUID().uuidString).json")
    }
}
