import Foundation
import NodeClubTrackerCore
import SQLite3
import XCTest

final class OpencodeSessionReaderTests: XCTestCase {
    /// 2026-09-16T12:00:00Z
    private static let now = Date(timeIntervalSince1970: 1_789_560_000)

    // 2026-09-16T10:00:00Z and 2026-09-15T09:00:00Z, in epoch ms.
    private static let todayMs: Int64 = 1_789_552_800_000
    private static let yesterdayMs: Int64 = 1_789_462_800_000

    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    // MARK: - Fixtures

    private func makeDatabase() -> URL {
        let fileManager = FileManager.default
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("opencode-test-\(UUID().uuidString)")
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let dbURL = dir.appendingPathComponent("opencode.db")

        var db: OpaquePointer?
        guard sqlite3_open_v2(dbURL.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else {
            fatalError("cannot open fixture db")
        }
        defer { sqlite3_close(db) }
        exec(db, """
        CREATE TABLE session (
            id text PRIMARY KEY,
            project_id text NOT NULL,
            directory text NOT NULL,
            time_created integer NOT NULL,
            time_updated integer NOT NULL
        )
        """)
        exec(db, """
        CREATE TABLE message (
            id text PRIMARY KEY,
            session_id text NOT NULL,
            time_created integer NOT NULL,
            time_updated integer NOT NULL,
            data text NOT NULL
        )
        """)
        insertSession(db, id: "ses_a", directory: "/tmp/projA")
        insertSession(db, id: "ses_b", directory: "/tmp/projB")
        insertSession(db, id: "ses_c", directory: "/tmp/projC")

        // projA / ses_a: nodeclub today (100), openrouter today (40 — filtered), user row (ignored)
        insertMessage(db, id: "m1", session: "ses_a", ts: Self.todayMs, data: assistant(
            provider: "nodeclub", model: "qwen3.8-27b",
            tokens: ["total": 100, "input": 60, "output": 40, "reasoning": 2, "cacheRead": 0, "cacheWrite": 0],
            cost: 0
        ))
        insertMessage(db, id: "m2", session: "ses_a", ts: Self.todayMs, data: assistant(
            provider: "openrouter", model: "deepseek-v4",
            tokens: ["total": 40, "input": 20, "output": 20],
            cost: 0.05
        ))
        insertMessage(db, id: "m3", session: "ses_a", ts: Self.todayMs, data: """
        {"role":"user","providerID":"nodeclub","modelID":"qwen3.8-27b","tokens":{"total":999,"input":999,"output":0}}
        """)

        // projB / ses_b: nodeclub yesterday (10)
        insertMessage(db, id: "m4", session: "ses_b", ts: Self.yesterdayMs, data: assistant(
            provider: "nodeclub", model: "qwen3.8-27b",
            tokens: ["total": 10, "input": 5, "output": 5],
            cost: 0
        ))

        // projC / ses_c: openrouter only → project must not appear (slightly earlier ts)
        insertMessage(db, id: "m5", session: "ses_c", ts: Self.todayMs - 1_000, data: assistant(
            provider: "openrouter", model: "deepseek-v4",
            tokens: ["total": 7, "input": 3, "output": 4],
            cost: 0
        ))
        return dbURL
    }

    private func exec(_ db: OpaquePointer, _ sql: String) {
        var error: UnsafeMutablePointer<CChar>?
        precondition(sqlite3_exec(db, sql, nil, nil, &error) == SQLITE_OK, "fixture exec failed: \(String(cString: error ?? nil))")
    }

    private func insertSession(_ db: OpaquePointer, id: String, directory: String) {
        var stmt: OpaquePointer?
        precondition(sqlite3_prepare_v2(db, "INSERT INTO session (id, project_id, directory, time_created, time_updated) VALUES (?,?,?,?,?)", -1, &stmt, nil) == SQLITE_OK)
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, (id as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, ("proj_\(id)" as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 3, (directory as NSString).utf8String, -1, nil)
        sqlite3_bind_int64(stmt, 4, Self.todayMs)
        sqlite3_bind_int64(stmt, 5, Self.todayMs)
        precondition(sqlite3_step(stmt) == SQLITE_DONE)
    }

    private func insertMessage(_ db: OpaquePointer, id: String, session: String, ts: Int64, data: String) {
        var stmt: OpaquePointer?
        precondition(sqlite3_prepare_v2(db, "INSERT INTO message (id, session_id, time_created, time_updated, data) VALUES (?,?,?,?,?)", -1, &stmt, nil) == SQLITE_OK)
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, (id as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (session as NSString).utf8String, -1, nil)
        sqlite3_bind_int64(stmt, 3, ts)
        sqlite3_bind_int64(stmt, 4, ts)
        sqlite3_bind_text(stmt, 5, (data as NSString).utf8String, -1, nil)
        precondition(sqlite3_step(stmt) == SQLITE_DONE)
    }

    private func assistant(
        provider: String,
        model: String,
        tokens: [String: Int],
        cost: Double
    ) -> String {
        let tokenJSON = tokens.map { "\"\($0.key)\":\($0.value)" }.joined(separator: ",")
        return """
        {"role":"assistant","providerID":"\(provider)","modelID":"\(model)","tokens":{\(tokenJSON)},"cost":\(cost),"time":{"created":0},"finish":"stop"}
        """
    }

    // MARK: - Tests

    func test_snapshotRollsUpWithProviderFilter() {
        let dbURL = makeDatabase()
        defer {
            try? FileManager.default.removeItem(
                at: dbURL.deletingLastPathComponent()
            )
        }

        let snapshot = OpencodeSessionReader.snapshot(
            databaseURL: dbURL,
            now: Self.now,
            calendar: Self.utcCalendar
        )
        // openrouter (40 + 7) and the user row (999) are excluded.
        XCTAssertEqual(snapshot.allTime.totalTokens, 110)
        XCTAssertEqual(snapshot.allTime.cost, 0, accuracy: 0.0001)
        XCTAssertEqual(snapshot.today.totalTokens, 100)
        XCTAssertEqual(snapshot.sessionCount, 2)
        XCTAssertEqual(snapshot.byModel.keys, Set(["qwen3.8-27b"]))
        XCTAssertEqual(snapshot.byModel["qwen3.8-27b"]?.totalTokens, 110)
        XCTAssertEqual(snapshot.todayByModel["qwen3.8-27b"]?.totalTokens, 100)
        XCTAssertEqual(snapshot.byDay["2026-09-16"]?.totalTokens, 100)
        XCTAssertEqual(snapshot.byDay["2026-09-15"]?.totalTokens, 10)
        // projC (openrouter-only) is absent; per-project session counts are 1 each.
        XCTAssertEqual(snapshot.byProject.map(\.name), ["projA", "projB"])
        XCTAssertEqual(snapshot.byProject[0].sessionCount, 1)
        XCTAssertEqual(snapshot.byProject[0].usage.totalTokens, 100)
        XCTAssertEqual(snapshot.byProject[1].usage.totalTokens, 10)
    }

    func test_snapshotProviderOverride() {
        let dbURL = makeDatabase()
        defer {
            try? FileManager.default.removeItem(at: dbURL.deletingLastPathComponent())
        }

        let snapshot = OpencodeSessionReader.snapshot(
            databaseURL: dbURL,
            providers: ["openrouter"],
            now: Self.now,
            calendar: Self.utcCalendar
        )
        XCTAssertEqual(snapshot.allTime.totalTokens, 47)
        XCTAssertEqual(snapshot.allTime.cost, 0.05, accuracy: 0.0001)
        XCTAssertEqual(snapshot.byProject.map(\.name), ["projA", "projC"])
    }

    func test_missingDatabaseIsEmpty() {
        let missing = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("missing-\(UUID().uuidString)/opencode.db")
        let snapshot = OpencodeSessionReader.snapshot(databaseURL: missing, now: Self.now, calendar: Self.utcCalendar)
        XCTAssertEqual(snapshot, .empty)
    }

    func test_corruptDatabaseIsEmpty() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("opencode-corrupt-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dbURL = dir.appendingPathComponent("opencode.db")
        try "this is not a sqlite database".write(to: dbURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: dir) }

        let snapshot = OpencodeSessionReader.snapshot(databaseURL: dbURL, now: Self.now, calendar: Self.utcCalendar)
        XCTAssertEqual(snapshot, .empty)
    }

    func test_defaultDataDirEnvOverride() throws {
        let dir = NSTemporaryDirectory() + "opencode-env-\(UUID().uuidString)"
        setenv("OPENCODE_DATA_DIR", dir, 1)
        defer { unsetenv("OPENCODE_DATA_DIR") }
        XCTAssertEqual(OpencodeSessionReader.defaultDataDir, URL(fileURLWithPath: dir, isDirectory: true))
        XCTAssertEqual(OpencodeSessionReader.defaultDatabaseURL.lastPathComponent, "opencode.db")
    }
}
