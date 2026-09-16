import Foundation
import Observation

/// Observable dashboard state: live agents + usage stats.
///
/// `refresh()` does all file I/O and the herdr subprocess off the main actor,
/// then publishes the results here. Both sources are best-effort: if one
/// fails, the other still updates.
@MainActor
@Observable
public final class PiDashboardModel {
    public private(set) var agents: [PiAgentMonitor.Agent] = []
    public private(set) var snapshot: PiUsageSnapshot?
    public private(set) var lastRefresh: Date?
    private var autoRefreshTask: Task<Void, Never>?

    public init() {}

    public var workingCount: Int { agents.count { $0.status == .working } }
    public var idleCount: Int { agents.count { $0.status == .idle } }

    public func refresh() async {
        let sessionsDir = PiSessionReader.defaultSessionsDir
        let now = Date()
        let result = await Task.detached(priority: .utility) {
            (
                PiSessionReader.snapshot(sessionsDir: sessionsDir, now: now),
                PiAgentMonitor.fetchAgents()
            )
        }.value
        self.snapshot = result.0
        self.agents = result.1
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
