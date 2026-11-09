namespace AIUsage.Windows.Models;

public enum ProviderKind
{
    Cursor,
    Codex,
    Claude,
}

/// <summary>Cursor ダッシュボードの期間トグル（Mac UsageDuration と同順）</summary>
public enum UsageDuration
{
    Hours24,
    Days7,
    Days30,
    BillingCycle,
}

public enum CursorOnDemandState
{
    Disabled,
    Limited,
    Unlimited,
}

public sealed record CursorUsageEvent(
    double TimestampMs,
    string Model,
    string Kind,
    int TotalTokens,
    double Requests,
    int SpendCents);

public sealed record CursorDailySpendRow(
    double DayMs,
    string Category,
    int SpendCents,
    int TotalTokens);

/// <summary>Mac CursorUsageSnapshot 相当（ダッシュボード用）</summary>
public sealed record CursorUsageSnapshot(
    string? PlanName,
    double? TotalPercentUsed,
    double? AutoPercentUsed,
    double? ApiPercentUsed,
    CursorOnDemandState OnDemand,
    double OnDemandSpendDollars,
    double? OnDemandLimitDollars,
    int UsedRequests,
    int LimitRequests,
    DateTimeOffset? ResetsAt,
    DateTimeOffset FetchedAt,
    string? ErrorMessage);

public sealed record CursorDashboardBundle(
    CursorUsageSnapshot Snapshot,
    IReadOnlyList<CursorUsageEvent> Events,
    IReadOnlyList<CursorDailySpendRow> DailySpend);

public sealed record UsageWindow(string Label, double RemainingPercent, DateTimeOffset? ResetsAt)
{
    public string PercentText => FormatPercent(RemainingPercent);

    public string CompactText(string resetStyle)
    {
        if (ResetsAt is not { } reset) return PercentText;
        var value = resetStyle switch
        {
            "clock" => reset.ToLocalTime().ToString("H:mm"),
            "day" => reset.ToLocalTime().ToString("M/d"),
            _ => reset.ToLocalTime().ToString("M/d HH:mm"),
        };
        return $"{PercentText} (~{value})";
    }

    public static string FormatPercent(double value)
    {
        var rounded = Math.Round(value);
        return Math.Abs(value - rounded) < 0.05
            ? $"{(int)rounded}%"
            : $"{value.ToString("0.0", System.Globalization.CultureInfo.CurrentCulture)}%";
    }
}

public sealed record UsageSnapshot(
    ProviderKind Provider,
    bool IsInstalled,
    IReadOnlyList<UsageWindow> Windows,
    string CompactText,
    string MenuText,
    string? PlanName,
    double? RemainingPercent,
    string? ErrorCode = null,
    CursorDashboardBundle? CursorDashboard = null)
{
    public bool HasUsage => Windows.Count > 0;
}

public static class ProviderNames
{
    public static string DisplayName(ProviderKind provider, bool compact = false) => provider switch
    {
        ProviderKind.Cursor => "Cursor",
        ProviderKind.Codex => compact ? "ChatGPT" : "ChatGPT",
        ProviderKind.Claude => compact ? "Claude" : "Claude Code",
        _ => "AI Usage",
    };

    public static string Glyph(ProviderKind provider) => provider switch
    {
        ProviderKind.Cursor => "C",
        ProviderKind.Codex => "◎",
        ProviderKind.Claude => "✳",
        _ => "AI",
    };
}
