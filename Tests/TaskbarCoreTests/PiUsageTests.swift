import Foundation
import TaskbarCore
import XCTest

final class PiUsageTests: XCTestCase {
    func test_additionSumsAllFields() {
        let a = PiUsage(input: 10, output: 5, cacheRead: 1, cacheWrite: 2, reasoning: 3, totalTokens: 15, cost: 0.5, turnCount: 1)
        let b = PiUsage(input: 1, output: 1, totalTokens: 2, cost: 0.25, turnCount: 2)
        let sum = a + b
        XCTAssertEqual(sum.input, 11)
        XCTAssertEqual(sum.output, 6)
        XCTAssertEqual(sum.cacheRead, 1)
        XCTAssertEqual(sum.cacheWrite, 2)
        XCTAssertEqual(sum.reasoning, 3)
        XCTAssertEqual(sum.totalTokens, 17)
        XCTAssertEqual(sum.cost, 0.75, accuracy: 0.0001)
        XCTAssertEqual(sum.turnCount, 3)
    }

    func test_tokensFormatting() {
        XCTAssertEqual(PiUsageFormat.tokens(0), "0")
        XCTAssertEqual(PiUsageFormat.tokens(999), "999")
        XCTAssertEqual(PiUsageFormat.tokens(1_000), "1k")
        XCTAssertEqual(PiUsageFormat.tokens(1_234), "1.2k")
        XCTAssertEqual(PiUsageFormat.tokens(150_000), "150k")
        XCTAssertEqual(PiUsageFormat.tokens(1_500_000), "1.5M")
    }

    func test_costFormatting() {
        XCTAssertEqual(PiUsageFormat.cost(0), "")
        XCTAssertEqual(PiUsageFormat.cost(0.0041), "$0.004")
        XCTAssertEqual(PiUsageFormat.cost(0.5), "$0.50")
        XCTAssertEqual(PiUsageFormat.cost(12.345), "$12.35")
    }

    func test_relativeTime() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(RelativeTime.ago(from: now.addingTimeInterval(-10), now: now), "just now")
        XCTAssertEqual(RelativeTime.ago(from: now.addingTimeInterval(-5 * 60), now: now), "5m ago")
        XCTAssertEqual(RelativeTime.ago(from: now.addingTimeInterval(-2 * 3600), now: now), "2h ago")
        XCTAssertEqual(RelativeTime.ago(from: now.addingTimeInterval(-3 * 86_400), now: now), "3d ago")
    }
}
