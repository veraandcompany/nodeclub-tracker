import Foundation
import NodeClubTrackerCore
import SQLite3
import XCTest

final class HermesSessionReaderTests: XCTestCase {
    /// 2026-09-16T12:00:00Z
    private static let now = Date(timeIntervalSince1970: 1_789_560_000)
    private static let nowEpoch: Double = 1_789_560_000
    // 2026-09-16T10:00:00Z (today) and 2026-09-15T09:00:00Z (yesterday), epoch seconds.
    private static let todayEpoch: Double = 1_789_552_800
    private static let yesterdayEpoch: Double = 1_789_462_800

    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private static let nodeClubURL = "https://api.nodeclub.ai/v1"
    private static let openRouterURL = "https://openrouter.ai/api/v1"

    // MARK: - Fixtures

    private func makeHome() -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("hermes-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func openDatabase(_ dbURL: URL, create: Bool) -> OpaquePointer {
        var db: OpaquePointer?
        let flags = create ? (SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE) : SQLITE_OPEN_READONLY
        precondition(
            sqlite3_open_v2(dbURL.path, &db, flags, nil) == SQLITE_OK && db != nil,
            "cannot open fixture db"
        )
        return db!
    }

    private func makeDatabase(in dir: URL, withRouteTable: Bool = true) -> URL {
        let dbURL = dir.appendingPathComponent("state.db")
        let db = openDatabase(dbURL, create: true)
        defer { sqlite3_close(db) }
        exec(db, """
        CREATE TABLE sessions (
            id TEXT PRIMARY KEY,
            source TEXT NOT NULL,
            model TEXT,
            cwd TEXT,
            started_at REAL NOT NULL,
            ended_at REAL,
            end_reason TEXT,
            last_activity_at REAL,
            input_tokens INTEGER DEFAULT 0,
            output_tokens INTEGER DEFAULT 0,
            cache_read_tokens INTEGER DEFAULT 0,
            cache_write_tokens INTEGER DEFAULT 0,
            reasoning_tokens INTEGER DEFAULT 0,
            estimated_cost_usd REAL,
            api_call_count INTEGER DEFAULT 0,
            billing_provider TEXT,
            billing_base_url TEXT,
            billing_mode TEXT
        )
        """)
        exec(db, """
        CREATE TABLE messages (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id TEXT NOT NULL,
            role TEXT NOT NULL,
            content TEXT,
            timestamp REAL NOT NULL
        )
        """)
        if withRouteTable {
            exec(db, """
            CREATE TABLE session_model_usage (
                session_id TEXT NOT NULL,
                model TEXT NOT NULL,
                billing_provider TEXT NOT NULL DEFAULT '',
                billing_base_url TEXT NOT NULL DEFAULT '',
                billing_mode TEXT NOT NULL DEFAULT '',
                task TEXT NOT NULL DEFAULT '',
                api_call_count INTEGER NOT NULL DEFAULT 0,
                input_tokens INTEGER NOT NULL DEFAULT 0,
                output_tokens INTEGER NOT NULL DEFAULT 0,
                cache_read_tokens INTEGER NOT NULL DEFAULT 0,
                cache_write_tokens INTEGER NOT NULL DEFAULT 0,
                reasoning_tokens INTEGER NOT NULL DEFAULT 0,
                estimated_cost_usd REAL NOT NULL DEFAULT 0,
                actual_cost_usd REAL NOT NULL DEFAULT 0,
                first_seen REAL,
                last_seen REAL,
                PRIMARY KEY (session_id, model, billing_provider, billing_base_url, billing_mode, task)
            )
            """)
        }
        return dbURL
    }

    private func exec(_ db: OpaquePointer, _ sql: String) {
        var stmt: OpaquePointer?
        precondition(sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK)
        defer { sqlite3_finalize(stmt) }
        precondition(sqlite3_step(stmt) == SQLITE_DONE)
    }

    private func insertSession(
        _ db: OpaquePointer, id: String, source: String = "cli", model: String? = nil,
        cwd: String? = nil, startedAt: Double, endedAt: Double? = nil,
        endReason: String? = nil, lastActivityAt: Double? = nil,
        input: Int = 0, output: Int = 0, cost: Double = 0, apiCalls: Int = 0,
        baseURL: String? = nil
    ) {
        var stmt: OpaquePointer?
        precondition(sqlite3_prepare_v2(db, """
            INSERT INTO sessions (id, source, model, cwd, started_at, ended_at, end_reason,
                                  last_activity_at, input_tokens, output_tokens,
                                  estimated_cost_usd, api_call_count, billing_base_url)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)
            """, -1, &stmt, nil) == SQLITE_OK)
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, (id as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (source as NSString).utf8String, -1, nil)
        if let model { sqlite3_bind_text(stmt, 3, (model as NSString).utf8String, -1, nil) } else { sqlite3_bind_null(stmt, 3) }
        if let cwd { sqlite3_bind_text(stmt, 4, (cwd as NSString).utf8String, -1, nil) } else { sqlite3_bind_null(stmt, 4) }
        sqlite3_bind_double(stmt, 5, startedAt)
        if let endedAt { sqlite3_bind_double(stmt, 6, endedAt) } else { sqlite3_bind_null(stmt, 6) }
        if let endReason { sqlite3_bind_text(stmt, 7, (endReason as NSString).utf8String, -1, nil) } else { sqlite3_bind_null(stmt, 7) }
        if let lastActivityAt { sqlite3_bind_double(stmt, 8, lastActivityAt) } else { sqlite3_bind_null(stmt, 8) }
        sqlite3_bind_int64(stmt, 9, Int64(input))
        sqlite3_bind_int64(stmt, 10, Int64(output))
        sqlite3_bind_double(stmt, 11, cost)
        sqlite3_bind_int64(stmt, 12, Int64(apiCalls))
        if let baseURL { sqlite3_bind_text(stmt, 13, (baseURL as NSString).utf8String, -1, nil) } else { sqlite3_bind_null(stmt, 13) }
        precondition(sqlite3_step(stmt) == SQLITE_DONE)
    }

    private func insertRoute(
        _ db: OpaquePointer, session: String, model: String, baseURL: String,
        input: Int = 0, output: Int = 0, cacheRead: Int = 0, cacheWrite: Int = 0,
        reasoning: Int = 0, cost: Double = 0, apiCalls: Int = 0
    ) {
        var stmt: OpaquePointer?
        precondition(sqlite3_prepare_v2(db, """
            INSERT INTO session_model_usage (session_id, model, billing_provider, billing_base_url,
                                             api_call_count, input_tokens, output_tokens,
                                             cache_read_tokens, cache_write_tokens, reasoning_tokens,
                                             estimated_cost_usd)
            VALUES (?,?,?,?,?,?,?,?,?,?,?)
            """, -1, &stmt, nil) == SQLITE_OK)
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, (session as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (model as NSString).utf8String, -1, nil)
        let provider = baseURL.contains("nodeclub") ? "custom:nodeclub" : "openrouter"
        sqlite3_bind_text(stmt, 3, (provider as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 4, (baseURL as NSString).utf8String, -1, nil)
        sqlite3_bind_int64(stmt, 5, Int64(apiCalls))
        sqlite3_bind_int64(stmt, 6, Int64(input))
        sqlite3_bind_int64(stmt, 7, Int64(output))
        sqlite3_bind_int64(stmt, 8, Int64(cacheRead))
        sqlite3_bind_int64(stmt, 9, Int64(cacheWrite))
        sqlite3_bind_int64(stmt, 10, Int64(reasoning))
        sqlite3_bind_double(stmt, 11, cost)
        precondition(sqlite3_step(stmt) == SQLITE_DONE)
    }

    private func insertMessage(_ db: OpaquePointer, session: String, ts: Double, role: String = "assistant") {
        var stmt: OpaquePointer?
        precondition(sqlite3_prepare_v2(db, "INSERT INTO messages (session_id, role, content, timestamp) VALUES (?,?,?,?)", -1, &stmt, nil) == SQLITE_OK)
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, (session as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (role as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 3, ("row for \(session)" as NSString).utf8String, -1, nil)
        sqlite3_bind_double(stmt, 4, ts)
        precondition(sqlite3_step(stmt) == SQLITE_DONE)
    }

    private func snapshot(of dbURL: URL) -> UsageSnapshot {
        HermesSessionReader.snapshot(databaseURLs: [dbURL], now: Self.now, calendar: Self.utcCalendar)
    }

    // MARK: - Snapshot: provider filter

    func test_onlyNodeClubRoutesCount() {
        let home = makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let dbURL = makeDatabase(in: home)
        let db = openDatabase(dbURL, create: true)
        defer { sqlite3_close(db) }

        // ses_a: nodeclub (100/40) + openrouter (40/20) on the same session.
        insertSession(db, id: "ses_a", model: nil, cwd: "/tmp/projA", startedAt: Self.todayEpoch)
        insertRoute(db, session: "ses_a", model: "qwen3.8-27b", baseURL: Self.nodeClubURL,
                    input: 100, output: 40, cacheRead: 10, cacheWrite: 2, reasoning: 3, cost: 0.5, apiCalls: 3)
        insertRoute(db, session: "ses_a", model: "deepseek-v4", baseURL: Self.openRouterURL,
                    input: 40, output: 20, cost: 0.1, apiCalls: 2)
        // ses_b: openrouter only → excluded entirely, projB must not appear.
        insertSession(db, id: "ses_b", cwd: "/tmp/projB", startedAt: Self.todayEpoch)
        insertRoute(db, session: "ses_b", model: "deepseek-v4", baseURL: Self.openRouterURL,
                    input: 50, output: 10, apiCalls: 2)

        let snapshot = snapshot(of: dbURL)
        XCTAssertEqual(snapshot.allTime.input, 100)
        XCTAssertEqual(snapshot.allTime.output, 40)
        XCTAssertEqual(snapshot.allTime.totalTokens, 140)
        XCTAssertEqual(snapshot.allTime.cost, 0.5, accuracy: 0.0001)
        XCTAssertEqual(snapshot.allTime.turnCount, 3)
        XCTAssertEqual(snapshot.today, snapshot.allTime)
        XCTAssertEqual(snapshot.sessionCount, 1)
        XCTAssertEqual(Set(snapshot.byModel.keys), Set(["qwen3.8-27b"]))
        XCTAssertEqual(snapshot.byProject.map(\.name), ["projA"])
        XCTAssertEqual(snapshot.byProject[0].sessionCount, 1)
        XCTAssertEqual(snapshot.byProject[0].usage.totalTokens, 140)
        XCTAssertEqual(snapshot.byDay["2026-09-16"]?.totalTokens, 140)
    }

    // MARK: - Snapshot: day attribution

    func test_dayAttributionUsesStartedAt() {
        let home = makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let dbURL = makeDatabase(in: home)
        let db = openDatabase(dbURL, create: true)
        defer { sqlite3_close(db) }

        // Started today.
        insertSession(db, id: "ses_today", cwd: "/tmp/a", startedAt: Self.todayEpoch)
        insertRoute(db, session: "ses_today", model: "m1", baseURL: Self.nodeClubURL, input: 10, output: 10, apiCalls: 1)
        // Started yesterday; its activity timestamps are also yesterday.
        insertSession(db, id: "ses_yesterday", cwd: "/tmp/b", startedAt: Self.yesterdayEpoch,
                      lastActivityAt: Self.yesterdayEpoch + 1800)
        insertRoute(db, session: "ses_yesterday", model: "m1", baseURL: Self.nodeClubURL, input: 5, output: 5, apiCalls: 1)
        insertMessage(db, session: "ses_yesterday", ts: Self.yesterdayEpoch + 1800)

        let snapshot = snapshot(of: dbURL)
        XCTAssertEqual(snapshot.byDay["2026-09-16"]?.totalTokens, 20)
        XCTAssertEqual(snapshot.byDay["2026-09-15"]?.totalTokens, 10)
        XCTAssertEqual(snapshot.today.totalTokens, 20)
        XCTAssertEqual(snapshot.allTime.totalTokens, 30)
    }

    // MARK: - Snapshot: schema fallback

    func test_fallbackToSessionsRowsWithoutRouteTable() {
        let home = makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let dbURL = makeDatabase(in: home, withRouteTable: false)
        let db = openDatabase(dbURL, create: true)
        defer { sqlite3_close(db) }

        insertSession(db, id: "ses_a", model: "m1", cwd: "/tmp/projC", startedAt: Self.todayEpoch,
                      input: 70, output: 30, cost: 0.2, apiCalls: 4, baseURL: Self.nodeClubURL)
        insertSession(db, id: "ses_b", cwd: "/tmp/projD", startedAt: Self.todayEpoch,
                      input: 10, output: 10, apiCalls: 1, baseURL: Self.openRouterURL)

        let snapshot = snapshot(of: dbURL)
        XCTAssertEqual(snapshot.allTime.input, 70)
        XCTAssertEqual(snapshot.allTime.output, 30)
        XCTAssertEqual(snapshot.allTime.cost, 0.2, accuracy: 0.0001)
        XCTAssertEqual(snapshot.sessionCount, 1)
        XCTAssertEqual(Set(snapshot.byModel.keys), Set(["m1"]))
        XCTAssertEqual(snapshot.byProject.map(\.name), ["projC"])
    }

    // MARK: - Snapshot: resilience

    func test_missingDatabaseIsEmpty() {
        let missing = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("missing-\(UUID().uuidString)/state.db")
        let snapshot = HermesSessionReader.snapshot(databaseURLs: [missing], now: Self.now, calendar: Self.utcCalendar)
        XCTAssertEqual(snapshot, .empty)
    }

    func test_corruptDatabaseIsEmpty() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("hermes-corrupt-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dbURL = dir.appendingPathComponent("state.db")
        try "this is not a sqlite database".write(to: dbURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: dir) }

        let snapshot = snapshot(of: dbURL)
        XCTAssertEqual(snapshot, .empty)
    }

    // MARK: - Snapshot: projects

    func test_gatewaySessionsWithoutCwdUseFallbackProject() {
        let home = makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let dbURL = makeDatabase(in: home)
        let db = openDatabase(dbURL, create: true)
        defer { sqlite3_close(db) }

        insertSession(db, id: "ses_telegram", source: "telegram", cwd: nil, startedAt: Self.todayEpoch)
        insertRoute(db, session: "ses_telegram", model: "m1", baseURL: Self.nodeClubURL, input: 10, output: 5, apiCalls: 1)

        let snapshot = snapshot(of: dbURL)
        XCTAssertEqual(snapshot.allTime.totalTokens, 15)
        XCTAssertEqual(snapshot.byProject.map(\.name), ["Hermes"])
        XCTAssertEqual(snapshot.byProject[0].path, "")
        XCTAssertEqual(snapshot.byProject[0].sessionCount, 1)
    }

    func test_sessionWithMultipleNodeClubRoutesCountsSessionOnce() {
        let home = makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let dbURL = makeDatabase(in: home)
        let db = openDatabase(dbURL, create: true)
        defer { sqlite3_close(db) }

        // Two models on the same NodeClub endpoint in one session.
        insertSession(db, id: "ses_a", cwd: "/tmp/multi", startedAt: Self.todayEpoch)
        insertRoute(db, session: "ses_a", model: "model-a", baseURL: Self.nodeClubURL, input: 10, output: 10, apiCalls: 1)
        insertRoute(db, session: "ses_a", model: "model-b", baseURL: Self.nodeClubURL, input: 1, output: 1, apiCalls: 1)

        let snapshot = snapshot(of: dbURL)
        XCTAssertEqual(snapshot.allTime.totalTokens, 22)
        XCTAssertEqual(snapshot.sessionCount, 1)
        XCTAssertEqual(snapshot.byProject[0].sessionCount, 1)
        XCTAssertEqual(Set(snapshot.byModel.keys), Set(["model-a", "model-b"]))
    }

    // MARK: - Database discovery

    func test_profileDatabasesAreDiscoveredAndAggregated() throws {
        let home = makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let mainDB = makeDatabase(in: home)
        let profileDir = home.appendingPathComponent("profiles/coder", isDirectory: true)
        try FileManager.default.createDirectory(at: profileDir, withIntermediateDirectories: true)
        let profileDB = makeDatabase(in: profileDir)
        // Non-DB clutter in the profile dir must be ignored.
        try "junk".write(to: profileDir.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)

        let main = openDatabase(mainDB, create: true)
        defer { sqlite3_close(main) }
        insertSession(main, id: "ses_a", cwd: "/tmp/p1", startedAt: Self.todayEpoch)
        insertRoute(main, session: "ses_a", model: "m1", baseURL: Self.nodeClubURL, input: 10, output: 10, apiCalls: 1)

        let profile = openDatabase(profileDB, create: true)
        defer { sqlite3_close(profile) }
        insertSession(profile, id: "ses_b", cwd: "/tmp/p2", startedAt: Self.todayEpoch)
        insertRoute(profile, session: "ses_b", model: "m1", baseURL: Self.nodeClubURL, input: 5, output: 5, apiCalls: 1)

        let urls = HermesSessionReader.databaseURLs(homeDir: home)
        XCTAssertEqual(urls, [mainDB.resolvingSymlinksInPath(), profileDB.resolvingSymlinksInPath()])

        let snapshot = HermesSessionReader.snapshot(databaseURLs: urls, now: Self.now, calendar: Self.utcCalendar)
        XCTAssertEqual(snapshot.allTime.totalTokens, 30)
        XCTAssertEqual(snapshot.sessionCount, 2)
        XCTAssertEqual(snapshot.byProject.map(\.name), ["p1", "p2"])
    }

    // MARK: - Watcher

    func test_watcherListsOnlyLiveNodeClubSessions() {
        let home = makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let dbURL = makeDatabase(in: home)
        let db = openDatabase(dbURL, create: true)
        defer { sqlite3_close(db) }

        // Live, active 30s ago → working.
        insertSession(db, id: "s1", cwd: "/tmp/w1", startedAt: Self.todayEpoch, baseURL: Self.nodeClubURL)
        insertMessage(db, session: "s1", ts: Self.nowEpoch - 30)
        // Live, active 10 min ago → idle.
        insertSession(db, id: "s2", cwd: "/tmp/w2", startedAt: Self.todayEpoch,
                      lastActivityAt: Self.nowEpoch - 600, baseURL: Self.nodeClubURL)
        // Live on OpenRouter → excluded (strict NodeClub-only).
        insertSession(db, id: "s3", cwd: "/tmp/w3", startedAt: Self.todayEpoch, baseURL: Self.openRouterURL)
        insertMessage(db, session: "s3", ts: Self.nowEpoch - 10)
        // Ended → excluded even though recent.
        insertSession(db, id: "s4", cwd: "/tmp/w4", startedAt: Self.todayEpoch,
                      endedAt: Self.nowEpoch - 100, endReason: "cli_close", baseURL: Self.nodeClubURL)
        insertMessage(db, session: "s4", ts: Self.nowEpoch - 100)
        // Live but stale (no activity in 1 h) → excluded.
        insertSession(db, id: "s5", cwd: "/tmp/w5", startedAt: Self.nowEpoch - 7200,
                      lastActivityAt: Self.nowEpoch - 3600, baseURL: Self.nodeClubURL)

        let agents = HermesSessionWatcher.findAgents(databaseURLs: [dbURL], now: Self.now)
        XCTAssertEqual(agents.map(\.id), ["s1", "s2"])
        XCTAssertEqual(agents.map(\.status), [.working, .idle])
        XCTAssertEqual(agents.map(\.project), ["w1", "w2"])
    }

    func test_watcherUsesFreshestMessageWhenHeartbeatLags() {
        let home = makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let dbURL = makeDatabase(in: home)
        let db = openDatabase(dbURL, create: true)
        defer { sqlite3_close(db) }

        // Stale heartbeat (10 min) but a fresh message (30 s) → working.
        insertSession(db, id: "s1", cwd: "/tmp/w1", startedAt: Self.todayEpoch,
                      lastActivityAt: Self.nowEpoch - 600, baseURL: Self.nodeClubURL)
        insertMessage(db, session: "s1", ts: Self.nowEpoch - 30)

        let agents = HermesSessionWatcher.findAgents(databaseURLs: [dbURL], now: Self.now)
        XCTAssertEqual(agents.map(\.id), ["s1"])
        XCTAssertEqual(agents.map(\.status), [.working])
    }

    func test_watcherMissingDatabaseIsEmpty() {
        let missing = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("missing-\(UUID().uuidString)/state.db")
        XCTAssertTrue(HermesSessionWatcher.findAgents(databaseURLs: [missing], now: Self.now).isEmpty)
    }
}

final class NodeClubEndpointTests: XCTestCase {
    func test_isNodeClubMatchesHostOnly() {
        XCTAssertTrue(NodeClubEndpoint.isNodeClub("https://api.nodeclub.ai/v1"))
        XCTAssertTrue(NodeClubEndpoint.isNodeClub("https://api.nodeclub.ai"))
        XCTAssertTrue(NodeClubEndpoint.isNodeClub("https://api.nodeclub.ai/v2/anything"))
        XCTAssertTrue(NodeClubEndpoint.isNodeClub("HTTPS://API.NodeClub.AI/v1"))
        XCTAssertFalse(NodeClubEndpoint.isNodeClub("https://openrouter.ai/api/v1"))
        XCTAssertFalse(NodeClubEndpoint.isNodeClub("https://api.nodeclub.ai.evil.com/v1"))
        XCTAssertFalse(NodeClubEndpoint.isNodeClub("https://notapi.nodeclub.ai/v1"))
        XCTAssertFalse(NodeClubEndpoint.isNodeClub(nil))
        XCTAssertFalse(NodeClubEndpoint.isNodeClub(""))
        XCTAssertFalse(NodeClubEndpoint.isNodeClub("not a url"))
    }
}
