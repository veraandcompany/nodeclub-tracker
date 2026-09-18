import Foundation
import Observation

/// Observable dashboard state: live agents + usage stats (pi + OpenCode).
///
/// `refresh()` does all file/DB I/O off the main actor, then publishes the
/// results here. Each source is best-effort: if one fails, the other still
/// updates.
@MainActor
@Observable
public final class PiDashboardModel {
    public private(set) var agents: [PiAgent] = []
    public private(set) var piSnapshot: UsageSnapshot?
    public private(set) var opencodeSnapshot: UsageSnapshot?
    public private(set) var history: PiUsageHistory
    public private(set) var lastRefresh: Date?
    private var autoRefreshTask: Task<Void, Never>?

    /// Combined view of pi + OpenCode usage (nil before the first refresh).
    public var snapshot: UsageSnapshot? {
        guard let pi = piSnapshot, let oc = opencodeSnapshot else { return nil }
        return .merged(pi, oc)
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
            let combined = UsageSnapshot.merged(pi, opencode)
            let persisted = PiHistoryStore.load(url: historyFile)
            let merged = PiHistorySummary.merged(
                live: combined.byDay,
                with: persisted,
                retainedDays: 90,
                now: now,
                calendar: calendar
            )
            PiHistoryStore.save(merged, to: historyFile)
            return (pi, opencode, merged, PiSessionWatcher.findAgents(sessionsDir: sessionsDir, now: now))
        }.value
        self.piSnapshot = result.0
        self.opencodeSnapshot = result.1
        self.history = result.2
        self.agents = result.3
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
