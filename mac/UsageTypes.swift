import Foundation

enum ProviderKind: String, CaseIterable, Codable {
    case cursor
    case codex

    var displayName: String {
        switch self {
        case .cursor: return "Cursor"
        case .codex: return "Codex"
        }
    }
}

enum OnDemandDisplayState: String {
    case disabled
    case limited
    case unlimited
}

struct CursorUsageEvent {
    var timestamp: TimeInterval
    var model: String
    var kind: String
    var totalTokens: Int
    var requests: Double
    var spendCents: Int
}

struct CursorDailySpendRow {
    var day: TimeInterval
    var category: String
    var spendCents: Int
    var totalTokens: Int
}

enum UsageDuration: String, CaseIterable {
    case hours24 = "1d"
    case days7 = "7d"
    case days30 = "30d"
    case billingCycle = "billingCycle"

    var menuLabelKey: String {
        switch self {
        case .hours24: return "dash.duration.24h"
        case .days7: return "dash.duration.7d"
        case .days30: return "dash.duration.30d"
        case .billingCycle: return "dash.duration.cycle"
        }
    }
}

struct CursorUsageSnapshot {
    var planName: String?
    var totalPercentUsed: Double?
    var autoPercentUsed: Double?
    var apiPercentUsed: Double?
    var onDemand: OnDemandDisplayState
    var onDemandSpendDollars: Double
    var onDemandLimitDollars: Double?
    var usedRequests: Int
    var limitRequests: Int
    var resetsAt: Date?
    var fetchedAt: Date
    var errorMessage: String?

    var menuBarPercentText: String {
        if let pct = totalPercentUsed {
            return formatPercent(pct)
        }
        if limitRequests > 0 {
            return "\(usedRequests)/\(limitRequests)"
        }
        return "—"
    }

    var statusLineSuffix: String {
        let body = menuBarPercentText
        if let plan = planName, !plan.isEmpty, totalPercentUsed != nil {
            return "\(plan) | \(body)"
        }
        return body
    }
}

struct CodexUsageSnapshot {
    var weeklyUsedPercent: Double?
    var primaryUsedPercent: Double?
    var planType: String?
    var weeklyResetsAt: Date?
    var primaryResetsAt: Date?
    var fetchedAt: Date
    var errorMessage: String?

    /// メニューバーは週間枠（docs/providers.md）
    var menuBarPercentText: String {
        guard let pct = weeklyUsedPercent else { return "—" }
        return formatPercent(pct)
    }
}

struct CursorDashboardBundle {
    var snapshot: CursorUsageSnapshot
    var events: [CursorUsageEvent]
    var dailySpend: [CursorDailySpendRow]
}

func formatTokens(_ n: Int) -> String {
    let v = Double(n)
    if v >= 1_000_000_000 { return String(format: "%.1fB", v / 1_000_000_000) }
    if v >= 1_000_000 { return String(format: "%.1fM", v / 1_000_000) }
    if v >= 1_000 { return String(format: "%.1fK", v / 1_000) }
    return "\(n)"
}

func formatDollarsFromCents(_ cents: Int) -> String {
    String(format: "$%.2f", Double(cents) / 100)
}

func formatPercent(_ value: Double) -> String {
    let rounded = value.rounded()
    if abs(value - rounded) < 0.05 {
        return "\(Int(rounded))%"
    }
    return String(format: "%.1f%%", value)
}

func formatPlanName(_ raw: String?) -> String? {
    guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let labels: [String: String] = [
        "ultra": "Ultra", "pro": "Pro", "pro_plus": "Pro+", "proplus": "Pro+", "pro+": "Pro+",
        "business": "Business", "enterprise": "Enterprise", "team": "Team", "free": "Free", "hobby": "Hobby",
    ]
    if let label = labels[key] { return label }
    return key.split(whereSeparator: { $0 == "_" || $0 == " " || $0 == "-" })
        .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
        .joined(separator: " ")
}
