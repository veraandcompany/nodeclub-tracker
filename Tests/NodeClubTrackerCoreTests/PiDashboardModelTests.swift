import Foundation
import NodeClubTrackerCore
import XCTest

/// End-to-end tests of `PiDashboardModel.refresh()` against isolated paths:
/// `PI_SESSION_DIR` and `PI_HISTORY_FILE` point at a temp dir (the same
/// env-override pattern the reader tests use), so nothing under `~` is
/// touched. The OpenCode/Hermes reads inside refresh fall back to the real
/// (read-only) locations when present — assertions never depend on them.
@MainActor
final class PiDashboardModelTests: XCTestCase {
    private var tempDir: URL!

    private var sessionsDir: URL { tempDir.appendingPathComponent("sessions", isDirectory: true) }
    private var historyFile: URL { tempDir.appendingPathComponent("history.json") }

    override func setUp() {
        super.setUp()
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("nodeclub-tracker-model-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: sessionsDir, withIntermediateDirectories: true)
        setenv("PI_SESSION_DIR", sessionsDir.path, 1)
        setenv("PI_HISTORY_FILE", historyFile.path, 1)
    }

    override func tearDown() {
        unsetenv("PI_SESSION_DIR")
        unsetenv("PI_HISTORY_FILE")
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Tests

    func test_refreshWritesHistoryThenSkipsUnchangedWrite() async throws {
        try writeSession(named: "s1", input: 100, output: 50)
        let model = PiDashboardModel()

        await model.refresh()
        XCTAssertTrue(FileManager.default.fileExists(atPath: historyFile.path))
        // The fixture turn landed on today's day key (plus whatever live
        // OpenCode/Hermes data this machine has, hence >=).
        let today = model.history.days[PiDayKey.string(for: Date(), calendar: .current), default: .zero]
        XCTAssertGreaterThanOrEqual(today.totalTokens, 150)
        let bytes1 = try Data(contentsOf: historyFile)
        let mtime1 = try mtime(of: historyFile)

        // No new data → the idempotent merge must not rewrite the file.
        try await Task.sleep(for: .milliseconds(150))
        await model.refresh()

        let bytes2 = try Data(contentsOf: historyFile)
        let mtime2 = try mtime(of: historyFile)
        XCTAssertEqual(bytes1, bytes2)
        XCTAssertEqual(mtime1, mtime2)
    }

    func test_refreshRewritesHistoryWhenSessionsChange() async throws {
        try writeSession(named: "s1", input: 100, output: 50)
        let model = PiDashboardModel()

        await model.refresh()
        let bytes1 = try Data(contentsOf: historyFile)

        try writeSession(named: "s2", input: 500, output: 500)
        try await Task.sleep(for: .milliseconds(150))
        await model.refresh()

        let bytes2 = try Data(contentsOf: historyFile)
        XCTAssertNotEqual(bytes1, bytes2)
        let today = model.history.days[PiDayKey.string(for: Date(), calendar: .current), default: .zero]
        XCTAssertGreaterThanOrEqual(today.totalTokens, 1150)
    }

    // MARK: - Helpers

    /// One session file with a single NodeClub assistant turn timestamped
    /// "now", so it lands on the current local day.
    private func writeSession(named name: String, input: Int, output: Int) throws {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let iso = formatter.string(from: Date())
        let lines = [
            #"{"type":"session","version":3,"id":"\#(name)","timestamp":"\#(iso)","cwd":"/tmp/model-test-proj"}"#,
            #"{"type":"message","id":"m-\#(name)","parentId":null,"timestamp":"\#(iso)","message":{"role":"assistant","content":[],"provider":"nodeclub","model":"qwen3.8-27b","usage":{"input":\#(input),"output":\#(output),"cacheRead":0,"cacheWrite":0,"reasoning":0,"totalTokens":\#(input + output),"cost":{"total":0}},"stopReason":"stop"}}"#,
        ]
        try lines.joined(separator: "\n").write(to: sessionsDir.appendingPathComponent("\(name).jsonl"), atomically: true, encoding: .utf8)
    }

    private func mtime(of url: URL) throws -> Date {
        let values = try url.resourceValues(forKeys: [.contentModificationDateKey])
        return try XCTUnwrap(values.contentModificationDate)
    }
}
