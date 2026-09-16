import Foundation

/// Additive token/cost totals from pi-agent session files.
public struct PiUsage: Sendable, Codable, Equatable {
    public var input: Int
    public var output: Int
    public var cacheRead: Int
    public var cacheWrite: Int
    public var reasoning: Int
    public var totalTokens: Int
    public var cost: Double
    public var turnCount: Int

    public init(
        input: Int = 0,
        output: Int = 0,
        cacheRead: Int = 0,
        cacheWrite: Int = 0,
        reasoning: Int = 0,
        totalTokens: Int = 0,
        cost: Double = 0,
        turnCount: Int = 0
    ) {
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.cacheWrite = cacheWrite
        self.reasoning = reasoning
        self.totalTokens = totalTokens
        self.cost = cost
        self.turnCount = turnCount
    }

    public static let zero = PiUsage()

    public static func + (lhs: PiUsage, rhs: PiUsage) -> PiUsage {
        PiUsage(
            input: lhs.input + rhs.input,
            output: lhs.output + rhs.output,
            cacheRead: lhs.cacheRead + rhs.cacheRead,
            cacheWrite: lhs.cacheWrite + rhs.cacheWrite,
            reasoning: lhs.reasoning + rhs.reasoning,
            totalTokens: lhs.totalTokens + rhs.totalTokens,
            cost: lhs.cost + rhs.cost,
            turnCount: lhs.turnCount + rhs.turnCount
        )
    }

    public static func += (lhs: inout PiUsage, rhs: PiUsage) {
        lhs = lhs + rhs
    }
}

/// One assistant turn with usage, as recorded in a session file.
public struct PiTurn: Sendable, Equatable {
    public var timestamp: Date
    public var provider: String?
    public var model: String?
    public var usage: PiUsage

    public init(timestamp: Date, provider: String?, model: String?, usage: PiUsage) {
        self.timestamp = timestamp
        self.provider = provider
        self.model = model
        self.usage = usage
    }
}

/// A project (working directory) rollup across its session files.
public struct PiProjectUsage: Sendable, Equatable, Identifiable {
    public var id: String { path }
    public var name: String
    public var path: String
    public var usage: PiUsage
    public var sessionCount: Int
    public var lastActivity: Date?
}

/// Aggregated usage snapshot across all pi sessions.
public struct PiUsageSnapshot: Sendable, Equatable {
    public var allTime: PiUsage
    public var today: PiUsage
    public var byModel: [String: PiUsage]
    public var todayByModel: [String: PiUsage]
    public var byDay: [String: PiUsage]
    public var byProject: [PiProjectUsage]
    public var sessionCount: Int
    public var collectedAt: Date

    public init(
        allTime: PiUsage,
        today: PiUsage,
        byModel: [String: PiUsage],
        todayByModel: [String: PiUsage],
        byDay: [String: PiUsage],
        byProject: [PiProjectUsage],
        sessionCount: Int,
        collectedAt: Date
    ) {
        self.allTime = allTime
        self.today = today
        self.byModel = byModel
        self.todayByModel = todayByModel
        self.byDay = byDay
        self.byProject = byProject
        self.sessionCount = sessionCount
        self.collectedAt = collectedAt
    }

    public static let empty = PiUsageSnapshot(
        allTime: .zero,
        today: .zero,
        byModel: [:],
        todayByModel: [:],
        byDay: [:],
        byProject: [],
        sessionCount: 0,
        collectedAt: .distantPast
    )
}

// MARK: - Formatting

/// Presentation formatting for usage numbers. Pure + testable.
public enum PiUsageFormat {
    /// "999", "1.2k", "1.5M"
    public static func tokens(_ count: Int) -> String {
        func scaled(_ value: Double, _ suffix: String) -> String {
            var text = String(format: "%.1f", value)
            if text.hasSuffix(".0") { text = String(text.dropLast(2)) }
            return text + suffix
        }
        switch count {
        case ..<1_000: return "\(count)"
        case ..<1_000_000: return scaled(Double(count) / 1_000, "k")
        default: return scaled(Double(count) / 1_000_000, "M")
        }
    }

    /// "$0.004" / "$1.23" / "" when free
    public static func cost(_ amount: Double) -> String {
        guard amount > 0 else { return "" }
        return amount < 0.01 ? String(format: "$%.3f", amount) : String(format: "$%.2f", amount)
    }
}

/// Small, deterministic relative-time strings ("just now", "5m ago", "2d ago").
public enum RelativeTime {
    public static func ago(from date: Date, now: Date) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 45 { return "just now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(max(minutes, 1))m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        let days = hours / 24
        return "\(days)d ago"
    }
}
