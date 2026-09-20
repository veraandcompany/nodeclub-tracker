import Foundation
import NodeClubTrackerCore
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

    func test_mergedSumsSourcesAndMergesSharedProjects() {
        let t1 = Date(timeIntervalSince1970: 1_000_000)
        let t2 = Date(timeIntervalSince1970: 2_000_000)
        let t3 = Date(timeIntervalSince1970: 3_000_000)
        let a = UsageSnapshot(
            allTime: PiUsage(input: 10, output: 10, totalTokens: 20, turnCount: 2),
            today: PiUsage(input: 10, output: 10, totalTokens: 20, turnCount: 2),
            byModel: ["m1": PiUsage(totalTokens: 20, turnCount: 2)],
            todayByModel: ["m1": PiUsage(totalTokens: 20, turnCount: 2)],
            byDay: ["2026-09-16": PiUsage(totalTokens: 20, turnCount: 2)],
            byProject: [PiProjectUsage(name: "projA", path: "/tmp/projA", usage: PiUsage(totalTokens: 20, turnCount: 2), sessionCount: 1, lastActivity: t1)],
            sessionCount: 1,
            collectedAt: t1
        )
        let b = UsageSnapshot(
            allTime: PiUsage(input: 5, output: 5, totalTokens: 10, turnCount: 1),
            today: .zero, byModel: [:], todayByModel: [:], byDay: [:],
            byProject: [PiProjectUsage(name: "projA", path: "/tmp/projA", usage: PiUsage(totalTokens: 10, turnCount: 1), sessionCount: 2, lastActivity: t3)],
            sessionCount: 2,
            collectedAt: t2
        )
        let c = UsageSnapshot(
            allTime: PiUsage(input: 1, output: 1, totalTokens: 2, turnCount: 1),
            today: .zero, byModel: [:], todayByModel: [:], byDay: [:],
            byProject: [PiProjectUsage(name: "other", path: "/tmp/other", usage: PiUsage(totalTokens: 2, turnCount: 1), sessionCount: 1, lastActivity: t2)],
            sessionCount: 1,
            collectedAt: t1
        )

        let merged = UsageSnapshot.merged([a, b, c])
        XCTAssertEqual(merged.allTime.totalTokens, 32)
        XCTAssertEqual(merged.sessionCount, 4)
        XCTAssertEqual(merged.collectedAt, t2)
        // Same path across sources: one entry, summed usage/sessions, freshest activity.
        XCTAssertEqual(merged.byProject.map(\.path), ["/tmp/projA", "/tmp/other"])
        XCTAssertEqual(merged.byProject[0].usage.totalTokens, 30)
        XCTAssertEqual(merged.byProject[0].sessionCount, 3)
        XCTAssertEqual(merged.byProject[0].lastActivity, t3)
    }

    func test_mergedEmptyArrayIsEmpty() {
        XCTAssertEqual(UsageSnapshot.merged([]), .empty)
    }
}
