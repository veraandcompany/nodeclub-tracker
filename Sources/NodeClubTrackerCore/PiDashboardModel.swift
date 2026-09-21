import Foundation
import Observation

/// Observable dashboard state: live agents + usage stats (pi + OpenCode + Hermes).
///
/// `refresh()` does all file/DB I/O off the main actor, then publishes the
/// results here. Each source is best-effort: if one fails, the others still
/// update.
@MainActor
@Observable
public final class PiDashboardModel {
    public private(set) var agents: [PiAgent] = []
    public private(set) var piSnapshot: UsageSnapshot?
    public private(set) var opencodeSnapshot: UsageSnapshot?
    public private(set) var hermesSnapshot: UsageSnapshot?
    public private(set) var history: PiUsageHistory
    public private(set) var lastRefresh: Date?
    private var autoRefreshTask: Task<Void, Never>?
    /// Re-entrancy guard: set for the duration of one scan so a concurrent
    /// `refresh()` (popover opening while auto-refresh runs) skips instead
    /// of doubling the I/O.
    private var isRefreshing = false
    /// Optional chatty log sink (e.g. `VerboseLogger.log`); called from the
    /// detached refresh task with per-source detail lines. nil = silent.
    private let log: (@Sendable (String) -> Void)?

    /// Combined view of pi + OpenCode + Hermes usage (nil before the first refresh).
    public var snapshot: UsageSnapshot? {
        guard
            let pi = piSnapshot,
            let oc = opencodeSnapshot,
            let hermes = hermesSnapshot
        else { return nil }
        return .merged([pi, oc, hermes])
    }

    public init(log: (@Sendable (String) -> Void)? = nil) {
        self.history = PiUsageHistory()
        self.log = log
    }

    public var workingCount: Int { agents.count { $0.status == .working } }
    public var idleCount: Int { agents.count { $0.status == .idle } }

    public func refresh() async {
        guard !isRefreshing else {
            log?("refresh: skipped, one already in flight")
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        let sessionsDir = PiSessionReader.defaultSessionsDir
        let historyFile = PiHistoryStore.defaultFileURL
        let now = Date()
        let calendar = Calendar.current
        let started = Date()
        let log = self.log
        let result = await Task.detached(priority: .utility) {
            let pi = PiSessionReader.snapshot(sessionsDir: sessionsDir, now: now)
            log?("refresh: pi \(pi.sessionCount) sessions, \(pi.byProject.count) projects, today \(PiUsageFormat.tokens(pi.today.totalTokens)) tokens")
            let opencode = OpencodeSessionReader.snapshot(now: now)
            log?("refresh: opencode \(opencode.sessionCount) sessions, \(opencode.byProject.count) projects, today \(PiUsageFormat.tokens(opencode.today.totalTokens)) tokens")
            let hermes = HermesSessionReader.snapshot(now: now)
            log?("refresh: hermes \(hermes.sessionCount) sessions, \(hermes.byProject.count) projects, today \(PiUsageFormat.tokens(hermes.today.totalTokens)) tokens")
            let combined = UsageSnapshot.merged([pi, opencode, hermes])
            let persisted = PiHistoryStore.load(url: historyFile)
            // 366 days so the "Year" window stays complete; the JSON stays ~40 KB.
            let merged = PiHistorySummary.merged(
                live: combined.byDay,
                with: persisted,
                retainedDays: 366,
                now: now,
                calendar: calendar
            )
            // The merge is idempotent, so rewriting the same bytes every
            // cycle is pure disk wear: save only when something changed.
            if merged != persisted {
                PiHistoryStore.save(merged, to: historyFile)
            }
            let agents = (PiSessionWatcher.findAgents(sessionsDir: sessionsDir, now: now)
                + HermesSessionWatcher.findAgents(now: now))
                .sorted { $0.lastActivity > $1.lastActivity }
            log?("refresh: \(agents.count) agents, \(agents.count { $0.status == .working }) working, \(agents.count { $0.status == .idle }) idle")
            return (pi, opencode, hermes, merged, agents)
        }.value
        self.piSnapshot = result.0
        self.opencodeSnapshot = result.1
        self.hermesSnapshot = result.2
        self.history = result.3
        self.agents = result.4
        self.lastRefresh = now
        log?("refresh: done in \(Int((Date().timeIntervalSince(started) * 1000).rounded())) ms")
    }

    public func startAutoRefresh(interval: Duration = .seconds(20)) {
        guard autoRefreshTask == nil else { return }
        log?("auto-refresh: starting (interval: \(interval))")
        autoRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: interval)
            }
        }
    }

    public func stopAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
    }
}
