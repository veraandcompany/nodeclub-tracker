import Foundation
import NodeClubTrackerCore
import XCTest

final class PiSessionReaderTests: XCTestCase {
    /// 2026-09-16T12:00:00Z
    private static let now = Date(timeIntervalSince1970: 1_789_560_000)

    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    // 2026-09-16T10:00:xx (today) and 2026-09-15T09:00:00 (yesterday).
    private static let fixtureLines: [String] = [
        #"{"type":"session","version":3,"id":"s1","timestamp":"2026-09-16T10:00:00.000Z","cwd":"/tmp/projA"}"#,
        #"{"type":"message","id":"m1","parentId":null,"timestamp":"2026-09-16T10:00:01.000Z","message":{"role":"user","content":"hi"}}"#,
        #"{"type":"message","id":"m2","parentId":"m1","timestamp":"2026-09-16T10:00:02.000Z","message":{"role":"assistant","content":[],"provider":"nodeclub","model":"qwen3.8-27b","usage":{"input":100,"output":50,"cacheRead":10,"cacheWrite":5,"reasoning":3,"totalTokens":150,"cost":{"input":0.1,"output":0.2,"cacheRead":0,"cacheWrite":0,"total":0.3}},"stopReason":"stop"}}"#,
        #"{"type":"message","id":"m3","parentId":"m2","timestamp":"2026-09-15T09:00:00.000Z","message":{"role":"assistant","content":[],"provider":"nodeclub","model":"other-model","usage":{"input":7,"output":3,"cacheRead":0,"cacheWrite":0,"totalTokens":10,"cost":{"total":0}},"stopReason":"stop"}}"#,
        "this line is not json",
        #"{"type":"compaction","id":"c1","parentId":"m3","timestamp":"2026-09-16T10:05:00.000Z","summary":"sum"}"#,
    ]

    func test_parseSessionExtractsCwdAndAssistantTurnsOnly() {
        let session = PiSessionReader.parseSession(lines: Self.fixtureLines)
        XCTAssertEqual(session.cwd, "/tmp/projA")
        XCTAssertEqual(session.turns.count, 2)
        XCTAssertEqual(session.turns[0].model, "qwen3.8-27b")
        XCTAssertEqual(session.turns[0].usage.input, 100)
        XCTAssertEqual(session.turns[0].usage.cost, 0.3, accuracy: 0.0001)
    }

    func test_parseSessionSkipsMalformedLines() {
        let session = PiSessionReader.parseSession(lines: Self.fixtureLines)
        // 2 assistant turns despite the garbage line + user + compaction entries.
        XCTAssertEqual(session.turns.count, 2)
    }

    func test_parseSessionEmptyData() {
        let session = PiSessionReader.parseSession(data: Data())
        XCTAssertNil(session.cwd)
        XCTAssertTrue(session.turns.isEmpty)
    }

    func test_snapshotAggregatesTodayAndAllTime() {
        let dir = makeTempSessionsDir(
            sessions: [
                "/tmp/projA": [String(data: Self.fixtureLines.joined(separator: "\n").data(using: .utf8)!, as: UTF8.self)],
            ]
        )
        defer { try? FileManager.default.removeItem(at: dir) }

        let snapshot = PiSessionReader.snapshot(sessionsDir: dir, now: Self.now, calendar: Self.utcCalendar)
        // All time: 150 + 10 tokens; cost 0.3.
        XCTAssertEqual(snapshot.allTime.totalTokens, 160)
        XCTAssertEqual(snapshot.allTime.cost, 0.3, accuracy: 0.0001)
        // Today: only the 2026-09-16 turn.
        XCTAssertEqual(snapshot.today.totalTokens, 150)
        XCTAssertEqual(snapshot.today.turnCount, 1)
        // Per model.
        XCTAssertEqual(snapshot.byModel["qwen3.8-27b"]?.totalTokens, 150)
        XCTAssertEqual(snapshot.byModel["other-model"]?.totalTokens, 10)
        // Today-only per model: the yesterday turn is excluded.
        XCTAssertEqual(snapshot.todayByModel["qwen3.8-27b"]?.totalTokens, 150)
        XCTAssertNil(snapshot.todayByModel["other-model"])
        // Per day.
        XCTAssertEqual(snapshot.byDay["2026-09-16"]?.totalTokens, 150)
        XCTAssertEqual(snapshot.byDay["2026-09-15"]?.totalTokens, 10)
        // One project.
        XCTAssertEqual(snapshot.byProject.count, 1)
        XCTAssertEqual(snapshot.byProject[0].name, "projA")
        XCTAssertEqual(snapshot.byProject[0].sessionCount, 1)
        XCTAssertEqual(snapshot.sessionCount, 1)
    }

    func test_snapshotGroupsByProject() {
        let dir = makeTempSessionsDir(
            sessions: [
                "/tmp/projA": [sessionJSON(cwd: "/tmp/projA", timestamp: "2026-09-16T10:00:00.000Z", totalTokens: 100)],
                "/tmp/projB": [
                    sessionJSON(cwd: "/tmp/projB", timestamp: "2026-09-16T11:00:00.000Z", totalTokens: 10),
                    sessionJSON(cwd: "/tmp/projB", timestamp: "2026-09-16T12:00:00.000Z", totalTokens: 5),
                ],
            ]
        )
        defer { try? FileManager.default.removeItem(at: dir) }

        let snapshot = PiSessionReader.snapshot(sessionsDir: dir, now: Self.now, calendar: Self.utcCalendar)
        XCTAssertEqual(snapshot.byProject.count, 2)
        // Sorted by last activity desc: projB (12:00) before projA (10:00).
        XCTAssertEqual(snapshot.byProject[0].name, "projB")
        XCTAssertEqual(snapshot.byProject[0].sessionCount, 2)
        XCTAssertEqual(snapshot.byProject[0].usage.totalTokens, 15)
        XCTAssertEqual(snapshot.byProject[1].name, "projA")
        XCTAssertEqual(snapshot.sessionCount, 3)
    }

    func test_snapshotMissingDirectoryIsEmpty() {
        let missing = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("definitely-missing-\(UUID().uuidString)")
        let snapshot = PiSessionReader.snapshot(sessionsDir: missing, now: Self.now, calendar: Self.utcCalendar)
        XCTAssertEqual(snapshot.allTime, .zero)
        XCTAssertTrue(snapshot.byProject.isEmpty)
    }

    // MARK: - Helpers

    /// Session dir layout: <dir>/<encoded-cwd>/<n>.jsonl
    private func makeTempSessionsDir(sessions: [String: [String]]) -> URL {
        let fileManager = FileManager.default
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("pi-sessions-\(UUID().uuidString)")
        for (cwd, contents) in sessions {
            let encoded = cwd.replacingOccurrences(of: "/", with: "-")
            let projectDir = dir.appendingPathComponent(encoded)
            try? fileManager.createDirectory(at: projectDir, withIntermediateDirectories: true)
            for (index, content) in contents.enumerated() {
                let file = projectDir.appendingPathComponent("\(index).jsonl")
                try? content.write(to: file, atomically: true, encoding: .utf8)
            }
        }
        return dir
    }

    private func sessionJSON(cwd: String, timestamp: String, totalTokens: Int) -> String {
        """
        {"type":"session","version":3,"id":"s-\(totalTokens)","timestamp":"\(timestamp)","cwd":"\(cwd)"}
        {"type":"message","id":"m-\(totalTokens)","parentId":null,"timestamp":"\(timestamp)","message":{"role":"assistant","content":[],"provider":"nodeclub","model":"qwen3.8-27b","usage":{"input":\(totalTokens / 2),"output":\(totalTokens - totalTokens / 2),"totalTokens":\(totalTokens),"cost":{"total":0}},"stopReason":"stop"}}
        """
    }
}
