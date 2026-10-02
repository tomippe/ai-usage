import Foundation

enum CursorModelBreakdown {
    static func durationCutoff(_ duration: UsageDuration, resetAt: Date?, now: Date = Date()) -> TimeInterval {
        let nowMs = now.timeIntervalSince1970 * 1000
        switch duration {
        case .hours24:
            return nowMs - 86_400_000
        case .days7:
            return nowMs - 7 * 86_400_000
        case .days30:
            return nowMs - 30 * 86_400_000
        case .billingCycle:
            guard let resetAt else { return nowMs - 31 * 86_400_000 }
            let start = Calendar.current.date(byAdding: .month, value: -1, to: resetAt) ?? resetAt
            return start.timeIntervalSince1970 * 1000
        }
    }

    static func aggregateByModel(
        events: [CursorUsageEvent],
        dailySpend: [CursorDailySpendRow],
        duration: UsageDuration,
        resetAt: Date?,
        now: Date = Date(),
        quotaAware: Bool = true
    ) -> [(model: String, requests: Double, tokens: Int, spendCents: Int)] {
        let cutoff = durationCutoff(duration, resetAt: resetAt, now: now)
        var spendByCategory: [String: Int] = [:]
        for row in dailySpend where row.day >= cutoff {
            spendByCategory[row.category, default: 0] += row.spendCents
        }

        var map: [String: (requests: Double, tokens: Int, spendCents: Int)] = [:]
        for event in events where event.timestamp >= cutoff {
            var entry = map[event.model] ?? (0, 0, 0)
            entry.requests += event.requests
            entry.tokens += event.totalTokens
            let billable = (!quotaAware || event.kind == "On-Demand") ? event.spendCents : 0
            entry.spendCents += billable
            map[event.model] = entry
        }

        for (category, cents) in spendByCategory {
            var entry = map[category] ?? (0, 0, 0)
            entry.spendCents += cents
            map[category] = entry
        }

        return map.map { (model: $0.key, requests: $0.value.requests, tokens: $0.value.tokens, spendCents: $0.value.spendCents) }
            .sorted { $0.tokens > $1.tokens }
    }

    static func dailyTokenSeries(
        events: [CursorUsageEvent],
        duration: UsageDuration,
        resetAt: Date?,
        now: Date = Date()
    ) -> [(day: Date, totalTokens: Int)] {
        let stacked = dailyStackedTokenSeries(events: events, duration: duration, resetAt: resetAt, now: now)
        return stacked.days.map { day in
            let total = stacked.series.reduce(0) { $0 + ($1.tokensByDay[day] ?? 0) }
            return (day, total)
        }
    }

    /// 正本 dashboard.js の積み上げ棒用（モデル別・日別トークン）
    static func dailyStackedTokenSeries(
        events: [CursorUsageEvent],
        duration: UsageDuration,
        resetAt: Date?,
        now: Date = Date()
    ) -> (days: [Date], series: [(model: String, tokensByDay: [Date: Int])]) {
        let cutoff = durationCutoff(duration, resetAt: resetAt, now: now)
        let cal = Calendar.current
        var daySet = Set<Date>()
        var byModel: [String: [Date: Int]] = [:]

        for event in events where event.timestamp >= cutoff {
            let day = cal.startOfDay(for: Date(timeIntervalSince1970: event.timestamp / 1000))
            daySet.insert(day)
            var bucket = byModel[event.model] ?? [:]
            bucket[day, default: 0] += event.totalTokens
            byModel[event.model] = bucket
        }

        let days = daySet.sorted()
        let ranked = byModel.map { (model: $0.key, total: $0.value.values.reduce(0, +)) }
            .sorted { $0.total > $1.total }
            .map(\.model)
        let series = ranked.map { model in
            (model: model, tokensByDay: byModel[model] ?? [:])
        }
        return (days, series)
    }
}
