import Foundation
import TaskbarCore
import XCTest

@MainActor
final class ClockTickerTests: XCTestCase {
    func test_startUpdatesNowAndStopFreezesIt() async {
        let ticker = ClockTicker(now: .distantPast)
        ticker.start(interval: .milliseconds(20))
        defer { ticker.stop() }

        try? await Task.sleep(for: .milliseconds(120))
        XCTAssertGreaterThan(ticker.now, Date.distantPast)

        let frozen = ticker.now
        ticker.stop()
        try? await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(ticker.now, frozen)
    }

    func test_startIsIdempotent() async {
        let ticker = ClockTicker(now: .distantPast)
        ticker.start(interval: .milliseconds(20))
        ticker.start(interval: .milliseconds(20))
        defer { ticker.stop() }

        try? await Task.sleep(for: .milliseconds(120))
        XCTAssertGreaterThan(ticker.now, Date.distantPast)
    }
}
