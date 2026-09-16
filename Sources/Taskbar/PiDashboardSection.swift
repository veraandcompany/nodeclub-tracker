import SwiftUI
import TaskbarCore

/// The pi-agent dashboard: live agents, today's usage, per-project rollup.
struct PiDashboardSection: View {
    var model: PiDashboardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            agentsBlock
            if let snapshot = model.snapshot {
                todayBlock(snapshot)
                projectsBlock(snapshot)
            } else {
                Text("Loading pi stats…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - Live agents

    private var agentsBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Pi agents", systemImage: "terminal")
                    .font(.headline)
                Spacer()
                if model.workingCount > 0 {
                    Text("\(model.workingCount) working")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                if model.agents.isEmpty == false {
                    Text("\(model.agents.count) total")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if model.agents.isEmpty {
                Text("No agents detected")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(model.agents) { agent in
                    agentRow(agent)
                }
            }
        }
    }

    private func agentRow(_ agent: PiAgentMonitor.Agent) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(agent.status == .working ? Color.green : Color.secondary.opacity(0.5))
                .frame(width: 7, height: 7)
            Text(agent.project)
                .font(.callout)
                .lineLimit(1)
            if let label = agent.label, label != agent.project {
                Text("· \(label)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer()
            Text(agent.status == .working ? "working" : "idle")
                .font(.caption)
                .foregroundStyle(agent.status == .working ? Color.green : Color.secondary)
        }
        .padding(.vertical, 1)
    }

    // MARK: - Today

    private func todayBlock(_ snapshot: PiUsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Today")
                .font(.headline)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(PiUsageFormat.tokens(snapshot.today.totalTokens))
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("tokens")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                let costText = PiUsageFormat.cost(snapshot.today.cost)
                if !costText.isEmpty {
                    Text(costText)
                        .font(.callout.weight(.medium))
                        .monospacedDigit()
                }
            }
            Text(detailLine(snapshot.today))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func detailLine(_ usage: PiUsage) -> String {
        var parts = [
            "in \(PiUsageFormat.tokens(usage.input))",
            "out \(PiUsageFormat.tokens(usage.output))",
        ]
        if usage.cacheRead + usage.cacheWrite > 0 {
            parts.append("cache \(PiUsageFormat.tokens(usage.cacheRead + usage.cacheWrite))")
        }
        parts.append("\(usage.turnCount) turns")
        return parts.joined(separator: " · ")
    }

    // MARK: - Projects

    private func projectsBlock(_ snapshot: PiUsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Projects")
                .font(.headline)
            if snapshot.byProject.isEmpty {
                Text("No usage recorded yet")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(snapshot.byProject.prefix(5)) { project in
                    projectRow(project, now: snapshot.collectedAt)
                }
                if snapshot.byProject.count > 5 {
                    Text("+\(snapshot.byProject.count - 5) more projects")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func projectRow(_ project: PiProjectUsage, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack {
                Text(project.name)
                    .font(.callout)
                    .lineLimit(1)
                Spacer()
                Text(PiUsageFormat.tokens(project.usage.totalTokens))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                let costText = PiUsageFormat.cost(project.usage.cost)
                if !costText.isEmpty {
                    Text(costText)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            if let lastActivity = project.lastActivity {
                Text(RelativeTime.ago(from: lastActivity, now: now))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 1)
    }
}
