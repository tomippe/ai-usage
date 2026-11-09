namespace AIUsage.Windows.Models;

/// <summary>Mac CursorModelBreakdown 相当の集計</summary>
internal static class CursorModelBreakdown
{
    public static double DurationCutoffMs(UsageDuration duration, DateTimeOffset? resetAt, DateTimeOffset now)
    {
        var nowMs = now.ToUnixTimeMilliseconds();
        const long DayMs = 86_400_000L;
        return duration switch
        {
            UsageDuration.Hours24 => nowMs - DayMs,
            UsageDuration.Days7 => nowMs - 7L * DayMs,
            UsageDuration.Days30 => nowMs - 30L * DayMs,
            UsageDuration.BillingCycle => resetAt is { } r
                ? (r.AddMonths(-1)).ToUnixTimeMilliseconds()
                : nowMs - 31L * DayMs,
            _ => nowMs - 31L * DayMs,
        };
    }

    public static IReadOnlyList<(string Model, double Requests, int Tokens, int SpendCents)> AggregateByModel(
        IReadOnlyList<CursorUsageEvent> events,
        IReadOnlyList<CursorDailySpendRow> dailySpend,
        UsageDuration duration,
        DateTimeOffset? resetAt,
        DateTimeOffset now,
        bool quotaAware = true)
    {
        var cutoff = DurationCutoffMs(duration, resetAt, now);
        var spendByCategory = new Dictionary<string, int>(StringComparer.Ordinal);
        foreach (var row in dailySpend)
        {
            if (row.DayMs >= cutoff)
                spendByCategory[row.Category] = spendByCategory.GetValueOrDefault(row.Category) + row.SpendCents;
        }

        var map = new Dictionary<string, (double Requests, int Tokens, int SpendCents)>(StringComparer.Ordinal);
        foreach (var ev in events)
        {
            if (ev.TimestampMs < cutoff) continue;
            var entry = map.GetValueOrDefault(ev.Model);
            entry.Requests += ev.Requests;
            entry.Tokens += ev.TotalTokens;
            var billable = (!quotaAware || ev.Kind == "On-Demand") ? ev.SpendCents : 0;
            entry.SpendCents += billable;
            map[ev.Model] = entry;
        }

        foreach (var (category, cents) in spendByCategory)
        {
            var entry = map.GetValueOrDefault(category);
            entry.SpendCents += cents;
            map[category] = entry;
        }

        return map
            .Select(kv => (Model: kv.Key, Requests: kv.Value.Requests, Tokens: kv.Value.Tokens, SpendCents: kv.Value.SpendCents))
            .OrderByDescending(x => x.Tokens)
            .ToArray();
    }

    public static (IReadOnlyList<DateTime> Days, IReadOnlyList<(string Model, IReadOnlyDictionary<DateTime, int> TokensByDay)> Series)
        DailyStackedTokenSeries(
            IReadOnlyList<CursorUsageEvent> events,
            UsageDuration duration,
            DateTimeOffset? resetAt,
            DateTimeOffset now)
    {
        var cutoff = DurationCutoffMs(duration, resetAt, now);
        var daySet = new HashSet<DateTime>();
        var byModel = new Dictionary<string, Dictionary<DateTime, int>>(StringComparer.Ordinal);

        foreach (var ev in events)
        {
            if (ev.TimestampMs < cutoff) continue;
            var day = DateTimeOffset.FromUnixTimeMilliseconds((long)Math.Round(ev.TimestampMs)).Date;
            daySet.Add(day);
            if (!byModel.TryGetValue(ev.Model, out var bucket))
            {
                bucket = [];
                byModel[ev.Model] = bucket;
            }
            bucket[day] = bucket.GetValueOrDefault(day) + ev.TotalTokens;
        }

        var days = daySet.OrderBy(d => d).ToArray();
        var ranked = byModel
            .Select(kv => (Model: kv.Key, Total: kv.Value.Values.Sum()))
            .OrderByDescending(x => x.Total)
            .Select(x => x.Model)
            .ToArray();

        var series = new List<(string, IReadOnlyDictionary<DateTime, int>)>();
        foreach (var model in ranked)
        {
            if (!byModel.TryGetValue(model, out var inner)) continue;
            series.Add((model, inner));
        }

        return (days, series);
    }
}
