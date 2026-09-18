import Foundation

/// Read-only access to pi-agent session files (`~/.pi/agent/sessions/**/*.jsonl`).
///
/// Parsing is pure (line strings in, models out) so it is fully testable without
/// touching the filesystem. Never write to the sessions directory.
public enum PiSessionReader {
    /// `~/.pi/agent/sessions`, overridable via `PI_SESSION_DIR` (tests/dev).
    public static var defaultSessionsDir: URL {
        if let override = ProcessInfo.processInfo.environment["PI_SESSION_DIR"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return URL(fileURLWithPath: NSHomeDirectory() + "/.pi/agent/sessions", isDirectory: true)
    }

    /// Usage rollups are inference-specific: only assistant turns attributed to these
    /// providers are counted. `nodeclub` is the provider id in `~/.pi/agent/models.json`
    /// whose `baseUrl` is `https://api.nodeclub.ai/v1`, so filtering on it means
    /// "tokens served by NodeClub" — not tokens from any backend pi happens to use
    /// (lmstudio, openai, anthropic, …).
    public static let defaultProviders: Set<String> = ["nodeclub"]

    /// Active provider filter; `PI_PROVIDERS` (comma-separated ids) overrides the default.
    public static var providers: Set<String> {
        if let override = ProcessInfo.processInfo.environment["PI_PROVIDERS"] {
            let ids = Set(
                override.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            )
            if !ids.isEmpty { return ids }
        }
        return defaultProviders
    }

    // MARK: - Pure parsing

    /// Parse one session file's JSONL into its header cwd + assistant turns.
    /// Malformed lines are skipped, never fatal.
    public static func parseSession(data: Data) -> ParsedSession {
        let lines = String(decoding: data, as: UTF8.self)
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
        return parseSession(lines: lines)
    }

    public static func parseSession(lines: [String]) -> ParsedSession {
        var cwd: String?
        var turns: [PiTurn] = []
        for line in lines {
            guard
                let bytes = line.data(using: .utf8),
                let entry = try? JSONDecoder().decode(Entry.self, from: bytes)
            else { continue }
            if entry.type == "session", cwd == nil { cwd = entry.cwd }
            guard
                entry.type == "message",
                let message = entry.message,
                message.role == "assistant",
                let usage = message.usage,
                let timestamp = isoDate(entry.timestamp)
            else { continue }
            turns.append(PiTurn(
                timestamp: timestamp,
                provider: message.provider,
                model: message.model,
                usage: PiUsage(
                    input: usage.input ?? 0,
                    output: usage.output ?? 0,
                    cacheRead: usage.cacheRead ?? 0,
                    cacheWrite: usage.cacheWrite ?? 0,
                    reasoning: usage.reasoning ?? 0,
                    totalTokens: usage.totalTokens ?? ((usage.input ?? 0) + (usage.output ?? 0)),
                    cost: usage.cost?.total ?? 0,
                    turnCount: 1
                )
            ))
        }
        return ParsedSession(cwd: cwd, turns: turns)
    }

    // MARK: - Aggregation

    /// Scan a sessions directory and roll up all-time / today / per-project usage.
    /// Only turns whose provider is in `providers` (default: `Self.providers`) count;
    /// sessions with no matching turns are excluded entirely. `now` and `calendar`
    /// are injected so "today" is deterministic in tests.
    public static func snapshot(
        sessionsDir: URL,
        providers: Set<String>? = nil,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> UsageSnapshot {
        let fileManager = FileManager.default
        let providerFilter = providers ?? Self.providers
        let dayStart = calendar.startOfDay(for: now)
        var allTime = PiUsage.zero
        var today = PiUsage.zero
        var byModel: [String: PiUsage] = [:]
        var todayByModel: [String: PiUsage] = [:]
        var byDay: [String: PiUsage] = [:]
        var projects: [String: PiProjectUsage] = [:]
        var sessionCount = 0

        // Sessions are nested: <sessionsDir>/<project>/<file>.jsonl — recurse.
        guard let enumerator = fileManager.enumerator(
            at: sessionsDir,
            includingPropertiesForKeys: nil,
            options: []
        ) else { return .empty }

        while let url = enumerator.nextObject() as? URL {
            guard url.pathExtension == "jsonl" else { continue }
            guard let data = try? Data(contentsOf: url) else { continue }
            let session = parseSession(data: data)
            guard let cwd = session.cwd else { continue }
            // Inference-specific filter: keep only turns from the configured providers.
            let turns = session.turns.filter { turn in
                guard let provider = turn.provider else { return false }
                return providerFilter.contains(provider)
            }
            guard !turns.isEmpty else { continue }
            sessionCount += 1
            let projectName = (cwd as NSString).lastPathComponent
            projects[cwd, default: PiProjectUsage(
                name: projectName,
                path: cwd,
                usage: .zero,
                sessionCount: 0,
                lastActivity: nil
            )].sessionCount += 1

            for turn in turns {
                allTime += turn.usage
                byDay[PiDayKey.string(for: turn.timestamp, calendar: calendar), default: .zero] += turn.usage
                if turn.timestamp >= dayStart && turn.timestamp <= now {
                    today += turn.usage
                    if let model = turn.model { todayByModel[model, default: .zero] += turn.usage }
                }
                if let model = turn.model { byModel[model, default: .zero] += turn.usage }
                var project = projects[cwd]!
                project.usage += turn.usage
                project.lastActivity = max(project.lastActivity ?? turn.timestamp, turn.timestamp)
                projects[cwd] = project
            }
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
            sessionCount: sessionCount,
            collectedAt: now
        )
    }

    // MARK: - Wire format (subset of pi's session JSONL)

    private struct Entry: Decodable {
        let type: String
        let cwd: String?
        let timestamp: String?
        let message: Message?

        struct Message: Decodable {
            let role: String
            let provider: String?
            let model: String?
            let usage: Usage?

            struct Usage: Decodable {
                let input: Int?
                let output: Int?
                let cacheRead: Int?
                let cacheWrite: Int?
                let reasoning: Int?
                let totalTokens: Int?
                let cost: Cost?

                struct Cost: Decodable {
                    let total: Double?
                }
            }
        }
    }

    private static func isoDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

public struct ParsedSession: Sendable, Equatable {
    public var cwd: String?
    public var turns: [PiTurn]

    public init(cwd: String?, turns: [PiTurn]) {
        self.cwd = cwd
        self.turns = turns
    }
}
