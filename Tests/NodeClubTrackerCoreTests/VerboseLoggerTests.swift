import Foundation
import NodeClubTrackerCore
import XCTest

final class VerboseLoggerTests: XCTestCase {
    private let suiteName = "VerboseLoggerTests"
    private var defaults: UserDefaults!
    private var logURL: URL!
    private var oldLogURL: URL!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removeObject(forKey: VerboseLogger.verboseLoggingKey)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("verbose-logger-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        logURL = directory.appendingPathComponent("nodeclub-tracker.log")
        oldLogURL = directory.appendingPathComponent("nodeclub-tracker.log.old")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: logURL.deletingLastPathComponent())
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        logURL = nil
        oldLogURL = nil
        super.tearDown()
    }

    private func pinnedCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    // MARK: - Toggle gating

    func test_logIsNoOpWhenToggleOff() {
        defaults.set(false, forKey: VerboseLogger.verboseLoggingKey)
        VerboseLogger.log("silent", defaults: defaults, to: logURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: logURL.path))
    }

    func test_logWritesTimestampedLineWhenToggleOn() throws {
        defaults.set(true, forKey: VerboseLogger.verboseLoggingKey)
        VerboseLogger.log("hello world", defaults: defaults, to: logURL)
        let content = try String(contentsOf: logURL, encoding: .utf8)
        let pattern = /\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} \[info\] hello world\n/
        XCTAssertNotNil(content.wholeMatch(of: pattern), "unexpected log format: \(content)")
    }

    // MARK: - Appending

    func test_appendLinePinsTimestamp() throws {
        let calendar = pinnedCalendar()
        let components = DateComponents(year: 2026, month: 7, day: 3, hour: 14, minute: 22, second: 31)
        let fixed = calendar.date(from: components)!
        VerboseLogger.appendLine(level: .error, message: "boom", to: logURL, now: fixed, calendar: calendar)
        let content = try String(contentsOf: logURL, encoding: .utf8)
        XCTAssertEqual(content, "2026-07-03 14:22:31 [error] boom\n")
    }

    func test_appendLineAppendsToExistingFile() throws {
        let calendar = pinnedCalendar()
        let fixed = calendar.date(from: DateComponents(year: 2026, month: 7, day: 3))!
        VerboseLogger.appendLine(level: .info, message: "first", to: logURL, now: fixed, calendar: calendar)
        VerboseLogger.appendLine(level: .error, message: "second", to: logURL, now: fixed, calendar: calendar)
        let content = try String(contentsOf: logURL, encoding: .utf8)
        XCTAssertEqual(
            content,
            """
            2026-07-03 00:00:00 [info] first
            2026-07-03 00:00:00 [error] second

            """
        )
    }

    func test_rotationShiftsOneGeneration() throws {
        let oversized = String(repeating: "x", count: 2_000_001)
        try oversized.write(to: logURL, atomically: true, encoding: .utf8)
        VerboseLogger.appendLine(level: .info, message: "new", to: logURL)
        let rotated = try String(contentsOf: oldLogURL, encoding: .utf8)
        XCTAssertEqual(rotated.count, 2_000_001)
        let fresh = try String(contentsOf: logURL, encoding: .utf8)
        XCTAssertTrue(fresh.hasSuffix("[info] new\n"), "unexpected fresh log: \(fresh)")
        XCTAssertLessThan(fresh.count, 2_000)
    }

    func test_rotationIsNoOpUnderLimit() throws {
        try "small\n".write(to: logURL, atomically: true, encoding: .utf8)
        VerboseLogger.appendLine(level: .info, message: "new", to: logURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldLogURL.path))
        let content = try String(contentsOf: logURL, encoding: .utf8)
        XCTAssertTrue(content.hasPrefix("small\n"), "existing content must survive: \(content)")
        XCTAssertTrue(content.hasSuffix("[info] new\n"))
    }

    // MARK: - Timestamp

    func test_timestampPinsFormat() {
        let calendar = pinnedCalendar()
        let date = calendar.date(from: DateComponents(year: 2026, month: 1, day: 9, hour: 5, minute: 7, second: 8))!
        XCTAssertEqual(VerboseLogger.timestamp(for: date, calendar: calendar), "2026-01-09 05:07:08")
    }
}
