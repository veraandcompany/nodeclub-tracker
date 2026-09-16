import Foundation
import TaskbarCore
import XCTest

final class ClockTextTests: XCTestCase {
    // 2025-06-16 14:30:05 UTC (a Monday).
    private static var fixedDate: Date {
        var components = DateComponents()
        components.year = 2025
        components.month = 6
        components.day = 16
        components.hour = 14
        components.minute = 30
        components.second = 5
        let calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: components)!
    }

    private static let utc = TimeZone(identifier: "UTC")!

    func test_menuBarTimeIs24HourHourMinute() {
        XCTAssertEqual(ClockText.menuBarTime(at: Self.fixedDate, timeZone: Self.utc), "14:30")
    }

    func test_popoverTimeIncludesSeconds() {
        XCTAssertEqual(ClockText.popoverTime(at: Self.fixedDate, timeZone: Self.utc), "14:30:05")
    }

    func test_longDateUsesFullWeekdayAndMonth() {
        XCTAssertEqual(ClockText.longDate(at: Self.fixedDate, timeZone: Self.utc), "Monday, June 16")
    }

    func test_formattingRespectsTimeZone() {
        // 14:30 UTC is 09:30 in New York (EDT, UTC-4) on that date.
        let newYork = TimeZone(identifier: "America/New_York")!
        XCTAssertEqual(ClockText.menuBarTime(at: Self.fixedDate, timeZone: newYork), "09:30")
    }
}
