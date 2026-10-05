import Foundation

enum ProviderKind: String, CaseIterable, Codable {
    case cursor
    case codex
    case claude

    var displayName: String {
        switch self {
        case .cursor: return "Cursor"
        case .codex: return "Codex"
        case .claude: return "Claude Code"
        }
    }

    /// メニュー表示名（ChatGPT.app / Codex 枠）
    var menuDisplayName: String {
        switch self {
        case .cursor: return "Cursor"
        case .codex: return "ChatGPT"
        case .claude: return "Claude"
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

    /// メニュー一覧に出すとき（数字が取れているときだけ true）
    var hasMenuUsage: Bool {
        if errorMessage == "not_logged_in" { return false }
        if errorMessage != nil, totalPercentUsed == nil, limitRequests == 0 { return false }
        if totalPercentUsed != nil { return true }
        return limitRequests > 0
    }

    /// メニューバー／メニュー行の定額合計（残り％）
    var menuBarPercentText: String {
        if let pct = totalPercentUsed {
            return formatPercent(remainingPercent(fromUsed: pct))
        }
        if limitRequests > 0 {
            let left = max(0, limitRequests - usedRequests)
            return formatPercent(Double(left) / Double(limitRequests) * 100)
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

    var showsOnDemandInStatus: Bool {
        onDemand != .disabled
    }

    /// メニューバー／括弧内の「純正 … / API … [/ 従量]」
    func cursorAutoApiOnDemandText(localExchangeRate: Double?) -> String {
        let auto = autoPercentUsed.map { formatPercent(remainingPercent(fromUsed: $0)) } ?? "—"
        let api = apiPercentUsed.map { formatPercent(remainingPercent(fromUsed: $0)) } ?? "—"
        var text = String(format: NSLocalizedString("status.cursor_auto_api", comment: ""), auto, api)
        guard showsOnDemandInStatus else { return text }
        text += onDemandSuffix(localExchangeRate: localExchangeRate)
        return text
    }

    private func onDemandSuffix(localExchangeRate: Double?) -> String {
        CurrencyDisplayFormatter.menuBarOnDemandSuffix(dollars: onDemandSpendDollars, rate: localExchangeRate)
    }

    /// メニューバー: 純正 … / API … / ¥… (〜M/d HH:mm)
    func menuBarTitleText(localExchangeRate: Double?) -> String {
        var text = cursorAutoApiOnDemandText(localExchangeRate: localExchangeRate)
        if let reset = formatMenuBarTildeReset(date: resetsAt, style: .monthDayTime) {
            text += reset
        }
        return text
    }

    /// 親メニュー行: Cursor - Ultra 84.7% (純正 … / API … / ¥…)
    func cursorMenuItemTitle(localExchangeRate: Double?) -> String {
        let total = menuBarPercentText
        let plan = formatPlanName(planName) ?? planName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let detail = cursorAutoApiOnDemandText(localExchangeRate: localExchangeRate)
        if plan.isEmpty {
            return String(format: NSLocalizedString("menu.cursor_line_no_plan", comment: ""), total, detail)
        }
        return String(format: NSLocalizedString("menu.cursor_line", comment: ""), plan, total, detail)
    }
}

struct CodexUsageSnapshot {
    var weeklyUsedPercent: Double?
    var primaryUsedPercent: Double?
    var planType: String?
    var weeklyResetsAt: Date?
    var primaryResetsAt: Date?
    var rateLimitResetCreditsAvailable: Int?
    var fetchedAt: Date
    var errorMessage: String?

    var hasMenuUsage: Bool {
        primaryUsedPercent != nil || weeklyUsedPercent != nil
    }

    /// メニューバー: 93% (〜4:10) / 87% (〜10/12)（残り％）
    func menuBarTitleText() -> String {
        menuBarCompactLine() ?? "—"
    }

    func menuBarCompactLine() -> String? {
        var parts: [String] = []
        if let used = primaryUsedPercent {
            let rem = formatPercent(remainingPercent(fromUsed: used))
            parts.append(rem + (formatMenuBarTildeReset(date: primaryResetsAt, style: .clock) ?? ""))
        }
        if let used = weeklyUsedPercent {
            let rem = formatPercent(remainingPercent(fromUsed: used))
            parts.append(rem + (formatMenuBarTildeReset(date: weeklyResetsAt, style: .monthDay) ?? ""))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " / ")
    }

    /// 例: ChatGPT - Plus 5時間 98%(23:01) / 週間 75%(10/4) / 1回リセット可能
    func codexMenuItemTitle() -> String {
        var segments: [String] = []
        if let used = primaryUsedPercent {
            let rem = formatPercent(remainingPercent(fromUsed: used))
            let when = formatCodexResetClock(primaryResetsAt)
            segments.append(String(format: NSLocalizedString("menu.codex_primary_remaining", comment: ""), rem, when))
        }
        if let used = weeklyUsedPercent {
            let rem = formatPercent(remainingPercent(fromUsed: used))
            let when = formatCodexResetDay(weeklyResetsAt)
            segments.append(String(format: NSLocalizedString("menu.codex_weekly_remaining", comment: ""), rem, when))
        }
        if let count = rateLimitResetCreditsAvailable, count > 0 {
            segments.append(String(format: NSLocalizedString("menu.codex_reset_credits", comment: ""), count))
        }
        let plan = formatPlanName(planType).map { $0 + " " } ?? ""
        let name = ProviderKind.codex.menuDisplayName
        if segments.isEmpty {
            return "\(name) — " + NSLocalizedString("status.unavailable", comment: "")
        }
        return "\(name) - \(plan)\(segments.joined(separator: " / "))"
    }
}

struct ClaudeUsageSnapshot {
    var fiveHourUsedPercent: Double?
    var sevenDayUsedPercent: Double?
    var fiveHourResetsAt: Date?
    var sevenDayResetsAt: Date?
    var fetchedAt: Date
    var errorMessage: String?

    var hasMenuUsage: Bool {
        if errorMessage == "credential_access_required" { return true }
        if errorMessage == "not_logged_in" || errorMessage == "no_credentials" { return false }
        return fiveHourUsedPercent != nil || sevenDayUsedPercent != nil
    }

    var needsCredentialAccessPrompt: Bool {
        errorMessage == "credential_access_required"
    }

    func menuBarTitleText() -> String {
        menuBarCompactLine() ?? "—"
    }

    func menuBarCompactLine() -> String? {
        guard hasMenuUsage, !needsCredentialAccessPrompt else { return nil }
        var parts: [String] = []
        if let used = fiveHourUsedPercent {
            let rem = formatPercent(remainingPercent(fromUsed: used))
            parts.append(rem + (formatMenuBarTildeReset(date: fiveHourResetsAt, style: .clock) ?? ""))
        }
        if let used = sevenDayUsedPercent {
            let rem = formatPercent(remainingPercent(fromUsed: used))
            parts.append(rem + (formatMenuBarTildeReset(date: sevenDayResetsAt, style: .monthDay) ?? ""))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " / ")
    }

    func menuItemTitle() -> String {
        var parts: [String] = []
        if let used = fiveHourUsedPercent {
            parts.append(String(format: NSLocalizedString("menu.claude_five_hour", comment: ""), formatPercent(remainingPercent(fromUsed: used)), formatCodexResetClock(fiveHourResetsAt)))
        }
        if let used = sevenDayUsedPercent {
            parts.append(String(format: NSLocalizedString("menu.claude_seven_day", comment: ""), formatPercent(remainingPercent(fromUsed: used)), formatCodexResetDay(sevenDayResetsAt)))
        }
        return parts.isEmpty ? "Claude — " : "Claude - " + parts.joined(separator: " / ")
    }

    func claudeMenuItemTitle() -> String {
        if needsCredentialAccessPrompt {
            return NSLocalizedString("menu.claude_credential_access", comment: "")
        }
        return menuItemTitle()
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

func remainingPercent(fromUsed used: Double) -> Double {
    max(0, min(100, 100 - used))
}

func formatCodexResetClock(_ date: Date?) -> String {
    guard let date else { return "—" }
    let f = DateFormatter()
    f.locale = Locale.current
    f.dateFormat = "H:mm"
    return f.string(from: date)
}

func formatCodexResetDay(_ date: Date?) -> String {
    guard let date else { return "—" }
    let f = DateFormatter()
    f.locale = Locale.current
    f.dateFormat = "M/d"
    return f.string(from: date)
}

enum MenuBarTildeResetStyle {
    case clock
    case monthDay
    case monthDayTime
}

/// メニューバー用 `(〜4:10)` / `(〜10/12)` / `(〜10/10 19:15)`
func formatMenuBarTildeReset(date: Date?, style: MenuBarTildeResetStyle) -> String? {
    guard let date else { return nil }
    let inner: String
    switch style {
    case .clock:
        inner = formatCodexResetClock(date)
    case .monthDay:
        inner = formatCodexResetDay(date)
    case .monthDayTime:
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateFormat = "M/d HH:mm"
        inner = f.string(from: date)
    }
    guard inner != "—" else { return nil }
    return " (〜\(inner))"
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
        "plus": "Plus",
        "business": "Business", "enterprise": "Enterprise", "team": "Team", "free": "Free", "hobby": "Hobby",
    ]
    if let label = labels[key] { return label }
    return key.split(whereSeparator: { $0 == "_" || $0 == " " || $0 == "-" })
        .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
        .joined(separator: " ")
}
