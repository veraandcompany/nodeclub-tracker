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

    /// Combined view of pi + OpenCode + Hermes usage (nil before the first refresh).
    public var snapshot: UsageSnapshot? {
        guard
            let pi = piSnapshot,
            let oc = opencodeSnapshot,
            let hermes = hermesSnapshot
        else { return nil }
        return .merged([pi, oc, hermes])
    }

    public init() {
        self.history = PiUsageHistory()
    }

    public var workingCount: Int { agents.count { $0.status == .working } }
    public var idleCount: Int { agents.count { $0.status == .idle } }

    public func refresh() async {
        let sessionsDir = PiSessionReader.defaultSessionsDir
        let historyFile = PiHistoryStore.defaultFileURL
        let now = Date()
        let calendar = Calendar.current
        let result = await Task.detached(priority: .utility) {
            let pi = PiSessionReader.snapshot(sessionsDir: sessionsDir, now: now)
            let opencode = OpencodeSessionReader.snapshot(now: now)
            let hermes = HermesSessionReader.snapshot(now: now)
            let combined = UsageSnapshot.merged([pi, opencode, hermes])
            let persisted = PiHistoryStore.load(url: historyFile)
            let merged = PiHistorySummary.merged(
                live: combined.byDay,
                with: persisted,
                retainedDays: 90,
                now: now,
                calendar: calendar
            )
            PiHistoryStore.save(merged, to: historyFile)
            let agents = (PiSessionWatcher.findAgents(sessionsDir: sessionsDir, now: now)
                + HermesSessionWatcher.findAgents(now: now))
                .sorted { $0.lastActivity > $1.lastActivity }
            return (pi, opencode, hermes, merged, agents)
        }.value
        self.piSnapshot = result.0
        self.opencodeSnapshot = result.1
        self.hermesSnapshot = result.2
        self.history = result.3
        self.agents = result.4
        self.lastRefresh = now
    }

    public func startAutoRefresh(interval: Duration = .seconds(20)) {
        guard autoRefreshTask == nil else { return }
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
