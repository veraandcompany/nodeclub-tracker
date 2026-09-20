import Foundation
import SQLite3

/// Read-only access to Hermes Agent's SQLite state (`~/.hermes/state.db`,
/// plus `~/.hermes/profiles/<name>/state.db` for named profiles).
///
/// Hermes persists one row per session in `sessions` with session-cumulative
/// token/cost counters, and (schema ≥ 20) per-route attribution rows in
/// `session_model_usage` keyed by `(session, model, provider, base_url, mode,
/// task)`. Every API call's usage lands on the route that served it, so
/// filtering route rows on the NodeClub host counts exactly the tokens that
/// went to `api.nodeclub.ai` — even for sessions that switched providers
/// mid-run. Sessions whose usage never touched NodeClub are excluded entirely.
///
/// Like the other readers: system SQLite in read-only mode (Hermes runs WAL,
/// designed for concurrent readers), and a missing file, corrupt file, or
/// schema drift degrades to an empty snapshot instead of failing.
///
/// Day attribution: session totals are bucketed by `started_at` — the same
/// convention Hermes' own insights engine uses. A session that starts
/// yesterday and runs past midnight is lumped on its start day.
public enum HermesSessionReader {
    /// Hermes home: `HERMES_HOME` (tests/dev) or `~/.hermes`.
    public static var defaultHomeDir: URL {
        if let override = ProcessInfo.processInfo.environment["HERMES_HOME"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return URL(fileURLWithPath: NSHomeDirectory() + "/.hermes", isDirectory: true)
    }

    /// `state.db` in the home dir plus one per named profile, most stable order.
    /// URLs are symlink-resolved so (e.g. `/var` vs `/private/var`) compare equal.
    public static func databaseURLs(homeDir: URL = defaultHomeDir) -> [URL] {
        var urls: [URL] = []
        let main = homeDir.appendingPathComponent("state.db")
        if FileManager.default.fileExists(atPath: main.path) { urls.append(main.resolvingSymlinksInPath()) }
        let profiles = homeDir.appendingPathComponent("profiles", isDirectory: true)
        if let entries = try? FileManager.default.contentsOfDirectory(
            at: profiles, includingPropertiesForKeys: nil
        ) {
            for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let db = entry.appendingPathComponent("state.db")
                if FileManager.default.fileExists(atPath: db.path) { urls.append(db.resolvingSymlinksInPath()) }
            }
        }
        return urls
    }

    // MARK: - Snapshot

    /// Roll up NodeClub usage across the given databases (default: all
    /// discovered Hermes databases) into a `UsageSnapshot`.
    public static func snapshot(
        databaseURLs: [URL]? = nil,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> UsageSnapshot {
        let urls = databaseURLs ?? Self.databaseURLs()
        let perDatabase = urls.map { Self.snapshot(database: $0, now: now, calendar: calendar) }
        guard let first = perDatabase.first else { return .empty }
        return UsageSnapshot.merged([first] + perDatabase.dropFirst())
    }

    private static func snapshot(database dbURL: URL, now: Date, calendar: Calendar) -> UsageSnapshot {
        guard let db = openReadOnly(dbURL) else { return .empty }
        defer { sqlite3_close(db) }

        // Preferred: per-route rows (exact split for provider-switching sessions).
        // Fallback: session rows for pre-v20 databases without the route table —
        // then a session counts all-or-nothing by its stamped billing route.
        let sql = hasRouteTable(db) ? routeQuery : sessionQuery
        guard let stmt = prepare(db, sql) else { return .empty }
        defer { sqlite3_finalize(stmt) }

        var rows: [RouteRow] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard
                let sessionID = columnText(stmt, 9),
                let startedAt = columnDouble(stmt, 11)
            else { continue }
            rows.append(RouteRow(
                model: columnText(stmt, 0),
                baseURL: columnText(stmt, 1),
                input: Int(sqlite3_column_int64(stmt, 2)),
                output: Int(sqlite3_column_int64(stmt, 3)),
                cacheRead: Int(sqlite3_column_int64(stmt, 4)),
                cacheWrite: Int(sqlite3_column_int64(stmt, 5)),
                reasoning: Int(sqlite3_column_int64(stmt, 6)),
                cost: Double(sqlite3_column_double(stmt, 7)),
                apiCalls: Int(sqlite3_column_int64(stmt, 8)),
                sessionID: sessionID,
                cwd: columnText(stmt, 10),
                startedAt: Date(timeIntervalSince1970: startedAt),
                lastActive: Date(timeIntervalSince1970: columnDouble(stmt, 12) ?? startedAt)
            ))
        }
        return rollup(rows, now: now, calendar: calendar)
    }

    private static func hasRouteTable(_ db: OpaquePointer) -> Bool {
        let sql = "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'session_model_usage'"
        guard let stmt = prepare(db, sql) else { return false }
        defer { sqlite3_finalize(stmt) }
        return sqlite3_step(stmt) == SQLITE_ROW
    }

    /// Per-route attribution (schema ≥ 20). One row per (session, model,
    /// route, task); a session's NodeClub share is exactly its NodeClub rows.
    private static let routeQuery = """
    SELECT u.model,
           u.billing_base_url,
           u.input_tokens,
           u.output_tokens,
           u.cache_read_tokens,
           u.cache_write_tokens,
           u.reasoning_tokens,
           u.estimated_cost_usd,
           u.api_call_count,
           s.id,
           s.cwd,
           s.started_at,
           COALESCE((SELECT MAX(_freshest.v) FROM (
               SELECT s.last_activity_at AS v
               UNION ALL
               SELECT MAX(m.timestamp) AS v FROM messages m WHERE m.session_id = s.id
           ) _freshest), s.started_at)
    FROM session_model_usage AS u
    JOIN sessions AS s ON s.id = u.session_id
    """

    /// Session-level fallback for databases without `session_model_usage`.
    /// `last_activity_at` is a rate-limited heartbeat, so freshness is
    /// freshest-of(activity, latest message, start) — Hermes' own pattern.
    private static let sessionQuery = """
    SELECT model,
           billing_base_url,
           input_tokens,
           output_tokens,
           cache_read_tokens,
           cache_write_tokens,
           reasoning_tokens,
           estimated_cost_usd,
           api_call_count,
           id,
           cwd,
           started_at,
           COALESCE((SELECT MAX(_freshest.v) FROM (
               SELECT sessions.last_activity_at AS v
               UNION ALL
               SELECT MAX(m.timestamp) AS v FROM messages m WHERE m.session_id = sessions.id
           ) _freshest), started_at)
    FROM sessions
    """

    /// Aggregate NodeClub-routed rows into a snapshot. Sessions are bucketed
    /// on `started_at`; project = `cwd` (gateway sessions have none → "Hermes").
    private static func rollup(_ rows: [RouteRow], now: Date, calendar: Calendar) -> UsageSnapshot {
        let dayStart = calendar.startOfDay(for: now)
        var allTime = PiUsage.zero
        var today = PiUsage.zero
        var byModel: [String: PiUsage] = [:]
        var todayByModel: [String: PiUsage] = [:]
        var byDay: [String: PiUsage] = [:]
        var projects: [String: PiProjectUsage] = [:]
        var projectSessions: [String: Set<String>] = [:]
        var sessionIDs = Set<String>()

        for row in rows where NodeClubEndpoint.isNodeClub(row.baseURL) {
            let usage = PiUsage(
                input: row.input,
                output: row.output,
                cacheRead: row.cacheRead,
                cacheWrite: row.cacheWrite,
                reasoning: row.reasoning,
                totalTokens: row.input + row.output,
                cost: row.cost,
                turnCount: row.apiCalls
            )
            allTime += usage
            byDay[PiDayKey.string(for: row.startedAt, calendar: calendar), default: .zero] += usage
            if row.startedAt >= dayStart && row.startedAt <= now {
                today += usage
            }
            if let model = row.model, !model.isEmpty {
                byModel[model, default: .zero] += usage
                if row.startedAt >= dayStart && row.startedAt <= now {
                    todayByModel[model, default: .zero] += usage
                }
            }
            sessionIDs.insert(row.sessionID)

            let path = (row.cwd?.isEmpty == false) ? row.cwd! : ""
            let name = path.isEmpty ? "Hermes" : (path as NSString).lastPathComponent
            var project = projects[path] ?? PiProjectUsage(
                name: name,
                path: path,
                usage: .zero,
                sessionCount: 0,
                lastActivity: nil
            )
            project.usage += usage
            project.lastActivity = max(project.lastActivity ?? row.lastActive, row.lastActive)
            projects[path] = project
            projectSessions[path, default: []].insert(row.sessionID)
        }

        for (path, sessions) in projectSessions {
            projects[path]?.sessionCount = sessions.count
        }

        let byProject = projects.values.sorted {
            ($0.lastActivity ?? .distantPast) > ($1.lastActivity ?? .distantPast)
        }
        return UsageSnapshot(
            allTime: allTime,
            today: today,
            byModel: byModel,
            todayByModel: todayByModel,
            byDay: byDay,
            byProject: byProject,
            sessionCount: sessionIDs.count,
            collectedAt: now
        )
    }

    // MARK: - Wire rows

    private struct RouteRow {
        var model: String?
        var baseURL: String?
        var input: Int
        var output: Int
        var cacheRead: Int
        var cacheWrite: Int
        var reasoning: Int
        var cost: Double
        var apiCalls: Int
        var sessionID: String
        var cwd: String?
        var startedAt: Date
        var lastActive: Date
    }

    // MARK: - SQLite helpers

    private static func openReadOnly(_ url: URL) -> OpaquePointer? {
        var db: OpaquePointer?
        let result = sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil)
        guard result == SQLITE_OK, db != nil else {
            if db != nil { sqlite3_close(db) }
            return nil
        }
        return db
    }

    private static func prepare(_ db: OpaquePointer, _ sql: String) -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        return stmt
    }

    private static func columnText(_ stmt: OpaquePointer, _ index: Int32) -> String? {
        guard let cstring = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: cstring)
    }

    private static func columnDouble(_ stmt: OpaquePointer, _ index: Int32) -> Double? {
        sqlite3_column_type(stmt, index) == SQLITE_NULL ? nil : Double(sqlite3_column_double(stmt, index))
    }
}

/// Detects live Hermes agents from `state.db` — NodeClub-routed sessions only
/// (strict: a live Hermes on any other endpoint is not NodeClub activity).
///
/// Live = `ended_at IS NULL` (CLI exit stamps `cli_close`, runtime release
/// `agent_close`), recent by freshest-of(`last_activity_at`, latest message
/// timestamp, `started_at`) — `last_activity_at` alone is a ~60s rate-limited
/// heartbeat and must not be used by itself. The recent window also drops
/// sessions a crashed process never managed to end.
public enum HermesSessionWatcher {
    /// Freshest activity within this window → working (seconds).
    public static let defaultWorkingWindow: TimeInterval = 120
    /// Freshest activity within this window → idle; older sessions are not listed (seconds).
    public static let defaultRecentWindow: TimeInterval = 30 * 60

    public static func findAgents(
        databaseURLs: [URL]? = nil,
        now: Date = Date(),
        workingWindow: TimeInterval = defaultWorkingWindow,
        recentWindow: TimeInterval = defaultRecentWindow
    ) -> [PiAgent] {
        let urls = databaseURLs ?? HermesSessionReader.databaseURLs()
        var agents: [PiAgent] = []
        for dbURL in urls {
            agents.append(contentsOf: findAgents(database: dbURL, now: now, workingWindow: workingWindow, recentWindow: recentWindow))
        }
        return agents.sorted { $0.lastActivity > $1.lastActivity }
    }

    private static func findAgents(
        database dbURL: URL,
        now: Date,
        workingWindow: TimeInterval,
        recentWindow: TimeInterval
    ) -> [PiAgent] {
        guard let db = openReadOnly(dbURL) else { return [] }
        defer { sqlite3_close(db) }
        let sql = """
        SELECT s.id,
               s.cwd,
               s.billing_base_url,
               COALESCE((SELECT MAX(_freshest.v) FROM (
                   SELECT s.last_activity_at AS v
                   UNION ALL
                   SELECT MAX(m.timestamp) AS v FROM messages m WHERE m.session_id = s.id
               ) _freshest), s.started_at)
        FROM sessions AS s
        WHERE s.ended_at IS NULL
        """
        guard let stmt = prepare(db, sql) else { return [] }
        defer { sqlite3_finalize(stmt) }

        var agents: [PiAgent] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let sessionID = columnText(stmt, 0) else { continue }
            let lastActivity = Date(timeIntervalSince1970: Double(sqlite3_column_double(stmt, 3)))
            let age = now.timeIntervalSince(lastActivity)
            guard age <= recentWindow else { continue }
            // Strict NodeClub-only: the session's current billing route must be
            // the NodeClub endpoint (refreshed on every model switch).
            guard NodeClubEndpoint.isNodeClub(columnText(stmt, 2)) else { continue }
            let status: PiAgent.Status = age <= workingWindow ? .working : .idle
            let cwd = columnText(stmt, 1)
            let project = (cwd?.isEmpty == false) ? (cwd! as NSString).lastPathComponent : "Hermes"
            agents.append(PiAgent(id: sessionID, project: project, status: status, lastActivity: lastActivity))
        }
        return agents
    }

    // MARK: - SQLite helpers

    private static func openReadOnly(_ url: URL) -> OpaquePointer? {
        var db: OpaquePointer?
        let result = sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil)
        guard result == SQLITE_OK, db != nil else {
            if db != nil { sqlite3_close(db) }
            return nil
        }
        return db
    }

    private static func prepare(_ db: OpaquePointer, _ sql: String) -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        return stmt
    }

    private static func columnText(_ stmt: OpaquePointer, _ index: Int32) -> String? {
        guard let cstring = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: cstring)
    }
}
