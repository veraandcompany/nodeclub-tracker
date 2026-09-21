import SwiftUI
import NodeClubTrackerCore

/// The pi-agent dashboard: live agents, today's usage, per-project rollup.
struct PiDashboardSection: View {
    var model: PiDashboardModel

    /// Persisted so the user's view choice survives relaunches.
    @AppStorage("usagePeriod") private var period: PiUsagePeriod = .day

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            agentsBlock
            if let snapshot = model.snapshot {
                usageBlock(snapshot)
                if snapshot.today.totalTokens > 0 {
                    modelsBlock(snapshot)
                }
                historyBlock(snapshot)
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
                Label("Agents", systemImage: "terminal")
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

    private func agentRow(_ agent: PiAgent) -> some View {
        let now = model.lastRefresh ?? Date()
        return HStack(spacing: 8) {
            Circle()
                .fill(agent.status == .working ? Color.green : Color.secondary.opacity(0.5))
                .frame(width: 7, height: 7)
            Text(agent.project)
                .font(.callout)
                .lineLimit(1)
            Spacer()
            Text(agent.status == .working ? "working" : "idle")
                .font(.caption)
                .foregroundStyle(agent.status == .working ? Color.green : Color.secondary)
            Text(RelativeTime.ago(from: agent.lastActivity, now: now))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(width: 64, alignment: .trailing)
        }
        .padding(.vertical, 1)
    }

    // MARK: - Usage (windowed)

    /// Usage is inference-specific: only turns served by the configured providers count.
    private var providerFilterCaption: some View {
        let providers = PiSessionReader.providers.sorted()
        return Group {
            if PiSessionReader.providers == PiSessionReader.defaultProviders {
                Text("NodeClub only (api.nodeclub.ai/v1 · flat rate)")
            } else {
                Text("Providers: \(providers.joined(separator: ", "))")
            }
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
    }

    /// Per-source split of the selected period (pi / OpenCode / Hermes), from live data.
    private func sourceCaption(now: Date) -> some View {
        let pi = model.piSnapshot.map { PiHistorySummary.period(period, days: $0.byDay, now: now, calendar: .current) }
        let oc = model.opencodeSnapshot.map { PiHistorySummary.period(period, days: $0.byDay, now: now, calendar: .current) }
        let hermes = model.hermesSnapshot.map { PiHistorySummary.period(period, days: $0.byDay, now: now, calendar: .current) }
        return Group {
            if let pi, let oc, let hermes {
                Text(
                    "pi \(PiUsageFormat.tokens(pi.totalTokens)) · opencode \(PiUsageFormat.tokens(oc.totalTokens))"
                        + " · hermes \(PiUsageFormat.tokens(hermes.totalTokens))"
                )
            }
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
    }

    private func usageBlock(_ snapshot: UsageSnapshot) -> some View {
        let days = model.history.days
        let now = snapshot.collectedAt
        let usage = PiHistorySummary.period(period, days: days, now: now, calendar: .current)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Usage")
                    .font(.headline)
                Picker("", selection: $period) {
                    ForEach(PiUsagePeriod.allCases) { p in
                        Text(p.rawValue).tag(p)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 190)
            }
            providerFilterCaption
            sourceCaption(now: now)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(PiUsageFormat.tokens(usage.totalTokens))
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("tokens")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                let costText = PiUsageFormat.cost(usage.cost)
                if !costText.isEmpty {
                    Text(costText)
                        .font(.callout.weight(.medium))
                        .monospacedDigit()
                }
            }
            Text(detailLine(usage))
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

    // MARK: - Models

    private func modelsBlock(_ snapshot: UsageSnapshot) -> some View {
        let total = max(snapshot.today.totalTokens, 1)
        let models = snapshot.todayByModel.sorted { $0.value.totalTokens > $1.value.totalTokens }
        return VStack(alignment: .leading, spacing: 6) {
            Text("Models")
                .font(.headline)
            ForEach(Array(models), id: \.key) { name, usage in
                HStack {
                    Text(name)
                        .font(.callout)
                        .lineLimit(1)
                    Spacer()
                    Text(PiUsageFormat.tokens(usage.totalTokens))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Text("\(Int((Double(usage.totalTokens) / Double(total) * 100).rounded()))%")
                        .font(.caption)
                        .monospacedDigit()
                        .frame(width: 36, alignment: .trailing)
                }
                .padding(.vertical, 1)
            }
        }
    }

    // MARK: - History

    private func historyBlock(_ snapshot: UsageSnapshot) -> some View {
        let days = model.history.days
        let now = snapshot.collectedAt
        let calendar = Calendar.current
        let points = PiHistorySummary.series(days: days, length: 14, now: now, calendar: calendar)
        let week = PiHistorySummary.window(days: days, length: 7, now: now, calendar: calendar)
        let month = PiHistorySummary.window(days: days, length: 30, now: now, calendar: calendar)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("History")
                    .font(.headline)
                Spacer()
                Text(
                    "7d \(PiUsageFormat.tokens(week.totalTokens)) · 30d \(PiUsageFormat.tokens(month.totalTokens))"
                )
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            }
            chartBars(points)
            HStack {
                Text(points.first?.label ?? "")
                Spacer()
                Text("last 14 days")
                    .foregroundStyle(.tertiary)
                Spacer()
                Text(points.last?.label ?? "")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    private func chartBars(_ points: [PiDayPoint]) -> some View {
        let maxTokens = points.map(\.usage.totalTokens).max() ?? 0
        let todayKey = points.last?.key
        return HStack(alignment: .bottom, spacing: 3) {
            ForEach(points) { point in
                let ratio = maxTokens == 0 ? 0 : CGFloat(point.usage.totalTokens) / CGFloat(maxTokens)
                let height = max(2, ratio * 28)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(point.key == todayKey ? Color.green : Color.secondary.opacity(0.4))
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
            }
        }
        .frame(height: 28, alignment: .bottom)
    }

    // MARK: - Projects

    private func projectsBlock(_ snapshot: UsageSnapshot) -> some View {
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
