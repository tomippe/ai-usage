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

struct CursorUsageSnapshot {
    var planName: String?
    var totalPercentUsed: Double?
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
