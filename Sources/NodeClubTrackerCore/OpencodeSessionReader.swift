import Foundation
import SQLite3

/// Read-only access to OpenCode's SQLite store (`~/.local/share/opencode/opencode.db`).
///
/// OpenCode (opencode.ai) persists every message as a row in `message` whose `data`
/// column is JSON carrying `role`, `providerID`, `modelID`, `tokens`, and `cost`;
/// `session` carries the working directory. We roll up assistant turns with the same
/// provider-filter discipline as `PiSessionReader`: only turns whose `providerID` is in
/// the configured set count, so OpenCode sessions on other backends (openrouter,
/// anthropic, …) never pollute NodeClub numbers.
///
/// SQLite is read with the system library in read-only mode — WAL-safe while OpenCode
/// is writing, and a missing file, corrupt file, or schema drift all degrade to an
/// empty snapshot instead of failing.
public enum OpencodeSessionReader {
    /// OpenCode data root: `OPENCODE_DATA_DIR` (comma-separated; first entry) or
    /// `${XDG_DATA_HOME:-~/.local/share}/opencode`.
    public static var defaultDataDir: URL {
        let env = ProcessInfo.processInfo.environment
        if let override = env["OPENCODE_DATA_DIR"] {
            let first = override.split(separator: ",").first.map(String.init).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            if let first, !first.isEmpty {
                return URL(fileURLWithPath: first, isDirectory: true)
            }
        }
        let base = env["XDG_DATA_HOME"] ?? NSHomeDirectory() + "/.local/share"
        return URL(fileURLWithPath: base, isDirectory: true)
            .appendingPathComponent("opencode", isDirectory: true)
    }

    public static var defaultDatabaseURL: URL {
        defaultDataDir.appendingPathComponent("opencode.db")
    }

    /// Roll up OpenCode assistant turns into a `UsageSnapshot`. Only turns whose
    /// `providerID` is in `providers` (default: `PiSessionReader.providers`) count;
    /// rows without a usable directory are skipped.
    public static func snapshot(
        databaseURL: URL? = nil,
        providers: Set<String>? = nil,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> UsageSnapshot {
        let dbURL = databaseURL ?? defaultDatabaseURL
        let providerFilter = providers ?? PiSessionReader.providers
        guard let db = openReadOnly(dbURL) else { return .empty }
        defer { sqlite3_close(db) }

        var allTime = PiUsage.zero
        var today = PiUsage.zero
        var byModel: [String: PiUsage] = [:]
        var todayByModel: [String: PiUsage] = [:]
        var byDay: [String: PiUsage] = [:]
        var projects: [String: PiProjectUsage] = [:]
        var sessionsByProject: [String: Set<String>] = [:]
        var sessionIDs = Set<String>()
        let dayStart = calendar.startOfDay(for: now)

        let sql = """
        SELECT m.time_created,
               m.session_id,
               s.directory,
               json_extract(m.data, '$.providerID'),
               json_extract(m.data, '$.modelID'),
               COALESCE(json_extract(m.data, '$.tokens.total'),
                        COALESCE(json_extract(m.data, '$.tokens.input'), 0)
                        + COALESCE(json_extract(m.data, '$.tokens.output'), 0)),
               COALESCE(json_extract(m.data, '$.tokens.input'), 0),
               COALESCE(json_extract(m.data, '$.tokens.output'), 0),
               COALESCE(json_extract(m.data, '$.tokens.reasoning'), 0),
               COALESCE(json_extract(m.data, '$.tokens.cache.read'), 0),
               COALESCE(json_extract(m.data, '$.tokens.cache.write'), 0),
               COALESCE(json_extract(m.data, '$.cost'), 0)
        FROM message AS m
        JOIN session AS s ON s.id = m.session_id
        WHERE json_extract(m.data, '$.role') = 'assistant'
        """
        guard let stmt = prepare(db, sql) else { return .empty }
        defer { sqlite3_finalize(stmt) }

        while sqlite3_step(stmt) == SQLITE_ROW {
            let timestamp = Date(timeIntervalSince1970: Double(sqlite3_column_int64(stmt, 0)) / 1000)
            guard
                let sessionId = columnText(stmt, 1),
                let directory = columnText(stmt, 2),
                !directory.isEmpty
            else { continue }
            guard let provider = columnText(stmt, 3), providerFilter.contains(provider) else { continue }

            let usage = PiUsage(
                input: Int(sqlite3_column_int64(stmt, 6)),
                output: Int(sqlite3_column_int64(stmt, 7)),
                cacheRead: Int(sqlite3_column_int64(stmt, 9)),
                cacheWrite: Int(sqlite3_column_int64(stmt, 10)),
                reasoning: Int(sqlite3_column_int64(stmt, 8)),
                totalTokens: Int(sqlite3_column_int64(stmt, 5)),
                cost: Double(sqlite3_column_double(stmt, 11)),
                turnCount: 1
            )

            allTime += usage
            byDay[PiDayKey.string(for: timestamp, calendar: calendar), default: .zero] += usage
            if timestamp >= dayStart && timestamp <= now {
                today += usage
            }
            if let model = columnText(stmt, 4) {
                byModel[model, default: .zero] += usage
                if timestamp >= dayStart && timestamp <= now {
                    todayByModel[model, default: .zero] += usage
                }
            }
            sessionIDs.insert(sessionId)
            sessionsByProject[directory, default: []].insert(sessionId)

            let projectName = (directory as NSString).lastPathComponent
            var project = projects[directory] ?? PiProjectUsage(
                name: projectName,
                path: directory,
                usage: .zero,
                sessionCount: 0,
                lastActivity: nil
            )
            project.usage += usage
            project.lastActivity = max(project.lastActivity ?? timestamp, timestamp)
            projects[directory] = project
        }

        let byProject = projects.values
            .map { project in
                var project = project
                project.sessionCount = sessionsByProject[project.path]?.count ?? 1
                return project
            }
            .sorted { ($0.lastActivity ?? .distantPast) > ($1.lastActivity ?? .distantPast) }
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
