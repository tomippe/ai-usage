using System.Diagnostics;
using System.Globalization;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using AIUsage.Windows.Models;
using Microsoft.Data.Sqlite;

namespace AIUsage.Windows.Services;

internal static class ProviderAvailability
{
    private static readonly string LocalAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
    private static readonly string RoamingAppData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
    private static readonly string UserProfile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
    private static readonly Lazy<string?> ChatGPTAppIdCache = new(FindChatGPTAppIdUncached);
    private static readonly Lazy<string?> OpenAiCodexInstallCache = new(FindOpenAiCodexInstallUncached);

    public static string CursorDatabasePath => Path.Combine(
        RoamingAppData, "Cursor", "User", "globalStorage", "state.vscdb");

    public static string ClaudeDirectory => Path.Combine(UserProfile, ".claude");
    public static string ClaudeSnapshotPath => Path.Combine(ClaudeDirectory, "ai-usage-rate-limits.json");
    public static string CodexAuthPath => Path.Combine(UserProfile, ".codex", "auth.json");

    public static string? FindExecutable(string name)
    {
        var candidates = new List<string>();
        var extensions = new[] { ".exe", ".cmd", ".bat" };
        foreach (var folder in (Environment.GetEnvironmentVariable("PATH") ?? "").Split(Path.PathSeparator))
        {
            if (string.IsNullOrWhiteSpace(folder)) continue;
            foreach (var extension in extensions) candidates.Add(Path.Combine(folder.Trim('"'), name + extension));
        }
        foreach (var candidate in candidates)
            if (File.Exists(candidate)) return candidate;
        return null;
    }

    public static string? FindCursorApp()
    {
        var candidates = new List<string>
        {
            Path.Combine(LocalAppData, "Programs", "Cursor", "Cursor.exe"),
            Path.Combine(LocalAppData, "Programs", "cursor", "Cursor.exe"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "Cursor", "Cursor.exe"),
            Path.Combine(RoamingAppData, "Cursor", "Cursor.exe"),
        };
        var programs = Path.Combine(LocalAppData, "Programs");
        if (Directory.Exists(programs))
        {
            foreach (var dir in Directory.EnumerateDirectories(programs))
            {
                var exe = Path.Combine(dir, "Cursor.exe");
                if (File.Exists(exe)) candidates.Add(exe);
            }
        }
        return candidates.FirstOrDefault(File.Exists);
    }

    public static string? FindChatGPTApp()
    {
        var candidates = new List<string>();
        // Store パッケージ内の ChatGPT.exe を最優先（WindowsApps のスタブより確実にアイコン付き）
        if (OpenAiCodexInstallCache.Value is { } installRoot)
        {
            candidates.Add(Path.Combine(installRoot, "app", "ChatGPT.exe"));
            candidates.Add(Path.Combine(installRoot, "app", "Codex.exe"));
        }
        candidates.AddRange(
        [
            Path.Combine(LocalAppData, "Programs", "ChatGPT", "ChatGPT.exe"),
            Path.Combine(LocalAppData, "Programs", "ChatGPT", "ChatGPT Desktop.exe"),
            Path.Combine(LocalAppData, "Programs", "chatgpt", "ChatGPT.exe"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "ChatGPT", "ChatGPT.exe"),
            Path.Combine(LocalAppData, "Microsoft", "WindowsApps", "chatgpt-desktop.exe"),
        ]);
        return candidates.FirstOrDefault(File.Exists);
    }

    /// <summary>Store 版 ChatGPT/Codex のブランドアイコン（.exe の汎用アイコンを避ける）。</summary>
    public static IEnumerable<string> FindChatGPTBrandIconPaths()
    {
        if (OpenAiCodexInstallCache.Value is not { } installRoot) yield break;

        var assets = Path.Combine(installRoot, "assets");
        var light = WindowsTheme.IsLightTaskbarShellTheme();
        var themed16 = Path.Combine(
            assets,
            light
                ? "Square44x44Logo.targetsize-16_altform-lightunplated.png"
                : "Square44x44Logo.targetsize-16_altform-unplated.png");
        if (File.Exists(themed16)) yield return themed16;

        foreach (var name in new[] { "Square44x44Logo.png", "icon.png" })
        {
            var p = Path.Combine(assets, name);
            if (File.Exists(p)) yield return p;
        }

        var res = Path.Combine(installRoot, "app", "resources");
        var themedIco = Path.Combine(res, light ? "chatgpt-app-light.ico" : "chatgpt-app-dark.ico");
        if (File.Exists(themedIco)) yield return themedIco;
        var brandIco = Path.Combine(res, "icon-chatgpt.ico");
        if (File.Exists(brandIco)) yield return brandIco;
    }

    public static string? FindCodexCommand()
    {
        var candidates = new List<string>
        {
            Path.Combine(LocalAppData, "Programs", "ChatGPT", "resources", "codex-cli", "bin", "codex.exe"),
            Path.Combine(LocalAppData, "Programs", "ChatGPT", "resources", "codex.exe"),
            Path.Combine(RoamingAppData, "npm", "codex.cmd"),
            Path.Combine(UserProfile, ".local", "bin", "codex.exe"),
        };
        if (OpenAiCodexInstallCache.Value is { } installRoot)
        {
            candidates.Add(Path.Combine(installRoot, "app", "resources", "codex.exe"));
            candidates.Add(Path.Combine(installRoot, "app", "Codex.exe"));
        }
        return candidates.FirstOrDefault(File.Exists) ?? FindExecutable("codex");
    }

    public static bool IsCursorInstalled => File.Exists(CursorDatabasePath) || FindCursorApp() is not null;
    public static bool IsCodexInstalled => File.Exists(CodexAuthPath) || FindCodexCommand() is not null || FindChatGPTAppId() is not null;
    public static bool IsClaudeInstalled =>
        File.Exists(Path.Combine(UserProfile, ".claude.json"))
        || File.Exists(Path.Combine(ClaudeDirectory, ".credentials.json"))
        || File.Exists(Path.Combine(ClaudeDirectory, "settings.json"))
        || FindExecutable("claude") is not null
        || File.Exists(ClaudeSnapshotPath);

    public static IReadOnlyList<ProviderKind> InstalledProviders()
    {
        var providers = new List<ProviderKind>();
        if (IsCursorInstalled) providers.Add(ProviderKind.Cursor);
        if (IsCodexInstalled) providers.Add(ProviderKind.Codex);
        if (IsClaudeInstalled) providers.Add(ProviderKind.Claude);
        return providers;
    }

    public static string? FindChatGPTAppId() => ChatGPTAppIdCache.Value;

    private static string? FindChatGPTAppIdUncached()
    {
        var result = RunPowerShell("(Get-StartApps | Where-Object { $_.Name -match 'ChatGPT|Codex' } | Select-Object -First 1 -ExpandProperty AppID)");
        return result;
    }

    private static string? FindOpenAiCodexInstallUncached() =>
        RunPowerShell("(Get-AppxPackage -Name 'OpenAI.Codex' | Select-Object -ExpandProperty InstallLocation -First 1)");

    private static string? RunPowerShell(string command)
    {
        try
        {
            var start = new ProcessStartInfo("powershell.exe")
            {
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardInput = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                ArgumentList = { "-NoProfile", "-NonInteractive", "-Command", command },
            };
            using var process = Process.Start(start);
            if (process is null) return null;
            var result = process.StandardOutput.ReadToEnd().Trim();
            if (!process.WaitForExit(5000)) process.Kill(true);
            return result.Length == 0 ? null : result;
        }
        catch { return null; }
    }
}

internal sealed class UsageService
{
    public async Task<IReadOnlyList<UsageSnapshot>> RefreshAllAsync(CancellationToken cancellationToken = default)
    {
        var providers = ProviderAvailability.InstalledProviders();
        var tasks = providers.Select(provider => provider switch
        {
            ProviderKind.Cursor => CursorUsageClient.FetchAsync(cancellationToken),
            ProviderKind.Codex => CodexUsageClient.FetchAsync(cancellationToken),
            _ => ClaudeUsageClient.ReadStatusLineSnapshotAsync(cancellationToken),
        });

        var results = await Task.WhenAll(tasks).ConfigureAwait(false);
        return results.OrderBy(s => s.Provider).ToArray();
    }

    public Task<UsageSnapshot> RefreshClaudeStatusLineAsync(CancellationToken cancellationToken = default) =>
        ClaudeUsageClient.ReadStatusLineSnapshotAsync(cancellationToken);
}

internal static class CursorUsageClient
{
    private const int TimeoutSeconds = 15;
    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(TimeoutSeconds) };
    private static readonly object CacheGate = new();
    private static (CursorAuth Auth, DateTimeOffset At)? _authCache;
    private static (string UserId, bool IsTeam, int? TeamId, int RequestLimit, bool OnDemand, string? Plan, DateTimeOffset At)? _setupCache;

    private sealed record CursorAuth(string UserId, string SessionToken, string? Email, string AccessToken);

    public static async Task<UsageSnapshot> FetchAsync(CancellationToken cancellationToken)
    {
        var installed = ProviderAvailability.IsCursorInstalled;
        if (!installed) return Empty(ProviderKind.Cursor, false, "not_installed");
        try
        {
            var bundle = await FetchDashboardBundleAsync(cancellationToken).ConfigureAwait(false);
            return await BuildUsageSnapshotFromBundleAsync(bundle, cancellationToken).ConfigureAwait(false);
        }
        catch (OperationCanceledException) { return Empty(ProviderKind.Cursor, installed, "timeout"); }
        catch { return Empty(ProviderKind.Cursor, installed, "unavailable"); }
    }

    private static async Task<CursorDashboardBundle> FetchDashboardBundleAsync(CancellationToken cancellationToken)
    {
        var fetchedAt = DateTimeOffset.UtcNow;
        var notInstalled = new CursorUsageSnapshot(null, null, null, null, CursorOnDemandState.Disabled, 0, null, 0, 0, null, fetchedAt, "not_installed");
        if (!ProviderAvailability.IsCursorInstalled) return new CursorDashboardBundle(notInstalled, [], []);
        var auth = LoadAuth();
        if (auth is null)
            return new CursorDashboardBundle(
                new CursorUsageSnapshot(null, null, null, null, CursorOnDemandState.Disabled, 0, null, 0, 0, null, fetchedAt, "not_logged_in"), [], []);
        var setup = await EnsureSetupAsync(auth, cancellationToken).ConfigureAwait(false);
        if (setup is null)
            return new CursorDashboardBundle(
                new CursorUsageSnapshot(null, null, null, null, CursorOnDemandState.Disabled, 0, null, 0, 0, null, fetchedAt, "setup_failed"), [], []);

        var snap = await BuildSoloOrTeamSnapshotAsync(auth, setup.Value, cancellationToken).ConfigureAwait(false);
        if (snap.ErrorMessage is { } err && err is "usage_failed" or "team_failed" or "team_member_missing")
            return new CursorDashboardBundle(snap, [], []);

        var events = await FetchUsageEventsAsync(auth, setup.Value, cancellationToken).ConfigureAwait(false);
        var daily = await FetchDailySpendRowsAsync(auth, setup.Value, cancellationToken).ConfigureAwait(false);
        return new CursorDashboardBundle(snap with { FetchedAt = DateTimeOffset.UtcNow }, events, daily);
    }

    private static async Task<CursorUsageSnapshot> BuildSoloOrTeamSnapshotAsync(
        CursorAuth auth,
        (string UserId, bool IsTeam, int? TeamId, int RequestLimit, bool OnDemand, string? Plan) setup,
        CancellationToken cancellationToken)
    {
        var now = DateTimeOffset.UtcNow;
        var headers = CursorHeaders(auth.SessionToken);
        var usage = await GetJsonAsync(
            $"https://cursor.com/api/usage?user={Uri.EscapeDataString(auth.UserId)}", headers, cancellationToken).ConfigureAwait(false);
        if (usage is null) return EmptySnapshot(now, "usage_failed");

        DateTimeOffset? reset = ParseDate(GetString(usage.RootElement, "startOfMonth"));
        if (reset is { } start)
        {
            var local = start.ToLocalTime();
            reset = new DateTimeOffset(local.Year, local.Month, 1, 0, 0, 0, local.Offset).AddMonths(1);
        }

        var totals = ExtractUsageTotals(usage.RootElement);
        var usedReq = totals.Used;
        var limitReq = totals.Limit;

        if (setup.IsTeam && setup.TeamId is { } teamId)
        {
            using var team = await PostJsonAsync(
                "https://cursor.com/api/dashboard/get-team-spend", headers,
                new { teamId }, cancellationToken).ConfigureAwait(false);
            if (team is null) return EmptySnapshot(now, "team_failed");

            var members = GetArray(team.RootElement, "teamMemberSpend");
            var me = members.FirstOrDefault(member =>
                string.Equals(GetString(member, "email"), auth.Email, StringComparison.OrdinalIgnoreCase)
                || MemberUserIdString(member) == auth.UserId);
            if (me.ValueKind == JsonValueKind.Undefined) return EmptySnapshot(now, "team_member_missing");

            var memberUsed = ToInt(GetValue(me, "includedRequestsUsed")) ?? ToInt(GetValue(me, "numRequests")) ?? 0;
            var memberLimit = ToInt(GetValue(me, "includedRequestLimit")) ?? ToInt(GetValue(me, "maxRequestUsage")) ?? setup.RequestLimit;
            var uTot = totals.Used;
            var lTot = totals.Limit;
            usedReq = uTot > 0 ? uTot : memberUsed;
            limitReq = lTot > 0 ? lTot : memberLimit;

            var cycle = ToDouble(GetValue(team.RootElement, "nextCycleStart"));
            if (cycle is > 0) reset = DateTimeOffset.FromUnixTimeMilliseconds((long)cycle.Value);
        }

        var onDemandState = setup.OnDemand ? CursorOnDemandState.Unlimited : CursorOnDemandState.Disabled;

        var snapshot = new CursorUsageSnapshot(
            setup.Plan, null, null, null, onDemandState, 0, null,
            usedReq, limitReq, reset, now, null);

        using var period = await PostJsonAsync(
            "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage",
            new Dictionary<string, string>
            {
                ["Authorization"] = $"Bearer {auth.AccessToken}",
                ["Connect-Protocol-Version"] = "1",
            }, new { }, cancellationToken).ConfigureAwait(false);

        if (period is null) return snapshot;
        ApplyPeriod(ref snapshot, period.RootElement, setup.OnDemand);
        return snapshot;
    }

    private static void ApplyPeriod(ref CursorUsageSnapshot s, JsonElement root, bool onDemandEnabled)
    {
        var planUsage = GetValue(root, "planUsage");
        var total = ClampPercent(ToDouble(GetValue(planUsage, "totalPercentUsed")));
        var auto = ClampPercent(ToDouble(GetValue(planUsage, "autoPercentUsed")));
        var api = ClampPercent(ToDouble(GetValue(planUsage, "apiPercentUsed")));
        DateTimeOffset? reset = s.ResetsAt;
        if (ToDouble(GetValue(root, "billingCycleEnd")) is { } billingCycleEnd && billingCycleEnd > 0)
            reset = DateTimeOffset.FromUnixTimeMilliseconds((long)billingCycleEnd);

        double? spendDollars = null;
        double? limitDollars = null;
        var spendLimit = GetValue(root, "spendLimitUsage");
        if (spendLimit.ValueKind == JsonValueKind.Object)
        {
            var limitCents = ToDouble(GetValue(spendLimit, "individualLimit")) ?? ToDouble(GetValue(spendLimit, "pooledLimit"));
            var usedCents = ToDouble(GetValue(spendLimit, "individualUsed")) ?? ToDouble(GetValue(spendLimit, "pooledUsed"));
            if (limitCents is > 0) limitDollars = limitCents / 100;
            if (usedCents is not null) spendDollars = usedCents / 100;
        }

        CursorOnDemandState onDemand;
        if (!onDemandEnabled) onDemand = CursorOnDemandState.Disabled;
        else if (limitDollars is > 0) onDemand = CursorOnDemandState.Limited;
        else onDemand = CursorOnDemandState.Unlimited;

        s = s with
        {
            TotalPercentUsed = total,
            AutoPercentUsed = auto,
            ApiPercentUsed = api,
            ResetsAt = reset,
            OnDemand = onDemand,
            OnDemandSpendDollars = spendDollars ?? s.OnDemandSpendDollars,
            OnDemandLimitDollars = onDemand == CursorOnDemandState.Limited ? limitDollars : null,
        };
    }

    private static CursorUsageSnapshot EmptySnapshot(DateTimeOffset at, string error) =>
        new(null, null, null, null, CursorOnDemandState.Disabled, 0, null, 0, 0, null, at, error);

    private static async Task<UsageSnapshot> BuildUsageSnapshotFromBundleAsync(CursorDashboardBundle bundle, CancellationToken cancellationToken)
    {
        var s = bundle.Snapshot;
        if (s.ErrorMessage == "not_installed") return Empty(ProviderKind.Cursor, false, "not_installed");
        if (s.ErrorMessage == "not_logged_in") return Empty(ProviderKind.Cursor, true, "not_logged_in");
        if (s.ErrorMessage is { } e && e is "usage_failed" or "team_failed" or "team_member_missing" or "setup_failed")
            return new UsageSnapshot(ProviderKind.Cursor, true, [], Localizer.Get("unavailable"),
                $"Cursor — {Localizer.Get("unavailable")}", s.PlanName, null, e, bundle);

        var windows = new List<UsageWindow>();
        DateTimeOffset? reset = s.ResetsAt;
        var autoUsed = ClampPercent(s.AutoPercentUsed);
        var apiUsed = ClampPercent(s.ApiPercentUsed);
        var totalUsed = ClampPercent(s.TotalPercentUsed);

        if (autoUsed is { } auto)
            windows.Add(new UsageWindow(Localizer.Get("auto"), 100 - auto, reset));
        if (apiUsed is { } api)
            windows.Add(new UsageWindow(Localizer.Get("api"), 100 - api, reset));
        if (windows.Count == 0 && totalUsed is { } total)
            windows.Add(new UsageWindow("Plan", 100 - total, reset));

        if (windows.Count == 0 && s.LimitRequests > 0)
            windows.Add(new UsageWindow("Plan", 100.0 * Math.Max(0, s.LimitRequests - s.UsedRequests) / s.LimitRequests, reset));

        var plan = s.PlanName;
        if (windows.Count == 0)
            return new UsageSnapshot(ProviderKind.Cursor, true, [], Localizer.Get("unavailable"),
                $"Cursor — {Localizer.Get("unavailable")}", plan, null, "no_usage", bundle);

        var onDemandBilling = s.OnDemand != CursorOnDemandState.Disabled;

        var compact = totalUsed is null && windows.Count > 1
            ? string.Join(" / ", windows.Select(w => w.PercentText))
            : totalUsed is not null && (autoUsed is not null || apiUsed is not null)
                ? string.Join(" / ", windows.Select(w => w.PercentText))
                : windows[0].PercentText;
        if (onDemandBilling && s.OnDemand != CursorOnDemandState.Disabled && s.OnDemandSpendDollars > 0)
        {
            var rate = await CurrencyService.GetRateAsync(Settings.Currency, cancellationToken).ConfigureAwait(false);
            compact += $" / {CurrencyService.FormatOnDemand(s.OnDemandSpendDollars, rate, Settings.Currency)}";
        }
        if (reset is { } when) compact += $" (~{when.ToLocalTime():M/d HH:mm})";

        var remaining = totalUsed is { } used
            ? 100 - used
            : s.LimitRequests > 0
                ? 100.0 * Math.Max(0, s.LimitRequests - s.UsedRequests) / s.LimitRequests
                : windows.Min(w => w.RemainingPercent);
        var planPrefix = string.IsNullOrWhiteSpace(plan) ? "" : $"{plan} ";
        var detailed = windows.Count > 1
            ? string.Join(" / ", windows.Select(w => $"{w.Label} {w.PercentText}"))
            : compact;
        var menu = $"Cursor - {planPrefix}{(totalUsed is not null || s.LimitRequests > 0 ? UsageWindow.FormatPercent(remaining) : compact)} ({detailed})";
        return new UsageSnapshot(ProviderKind.Cursor, true, windows, compact, menu, plan, remaining, null, bundle);
    }

    private static async Task<IReadOnlyList<CursorUsageEvent>> FetchUsageEventsAsync(
        CursorAuth auth,
        (string UserId, bool IsTeam, int? TeamId, int RequestLimit, bool OnDemand, string? Plan) setup,
        CancellationToken cancellationToken)
    {
        var headers = CursorJsonHeaders(auth.SessionToken);
        var teamId = setup.TeamId ?? 0;
        var endDate = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
        var startDate = endDate - 31L * 86_400_000L;
        var all = new List<CursorUsageEvent>();
        for (var page = 1; page <= 10; page++)
        {
            using var data = await PostJsonAsync(
                "https://cursor.com/api/dashboard/get-filtered-usage-events", headers,
                new Dictionary<string, object>
                {
                    ["teamId"] = teamId,
                    ["startDate"] = startDate.ToString(CultureInfo.InvariantCulture),
                    ["endDate"] = endDate.ToString(CultureInfo.InvariantCulture),
                    ["page"] = page,
                    ["pageSize"] = 500,
                },
                cancellationToken).ConfigureAwait(false);
            if (data is null) break;
            var events = GetArray(data.RootElement, "usageEventsDisplay");
            foreach (var e in events)
            {
                var tok = GetValue(e, "tokenUsage");
                var tokens = (ToInt(GetValue(tok, "inputTokens")) ?? 0)
                    + (ToInt(GetValue(tok, "outputTokens")) ?? 0)
                    + (ToInt(GetValue(tok, "cacheWriteTokens")) ?? 0)
                    + (ToInt(GetValue(tok, "cacheReadTokens")) ?? 0);
                var kindRaw = GetString(e, "kind") ?? "";
                string kind;
                if (kindRaw == "USAGE_EVENT_KIND_USAGE_BASED") kind = "On-Demand";
                else if (kindRaw.Contains("ERRORED", StringComparison.Ordinal)) kind = "Errored";
                else if (kindRaw.Contains("ABORTED", StringComparison.Ordinal)) kind = "Aborted";
                else kind = "Included";
                all.Add(new CursorUsageEvent(
                    ToDouble(GetValue(e, "timestamp")) ?? 0,
                    GetString(e, "model") ?? "unknown",
                    kind,
                    tokens,
                    ToDouble(GetValue(e, "requestsCosts")) ?? ToDouble(GetValue(e, "numRequests")) ?? 1,
                    ToInt(GetValue(e, "chargedCents")) ?? 0));
            }
            if (events.Length < 500) break;
        }
        return all;
    }

    private static async Task<IReadOnlyList<CursorDailySpendRow>> FetchDailySpendRowsAsync(
        CursorAuth auth,
        (string UserId, bool IsTeam, int? TeamId, int RequestLimit, bool OnDemand, string? Plan) setup,
        CancellationToken cancellationToken)
    {
        if (!setup.IsTeam || setup.TeamId is not { } teamId) return Array.Empty<CursorDailySpendRow>();
        var headers = CursorJsonHeaders(auth.SessionToken);
        var endMs = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
        var startMs = endMs - 31L * 86_400_000L;
        var dashboardUserId = await ResolveDashboardUserIdAsync(auth, headers, setup, cancellationToken).ConfigureAwait(false);
        if (dashboardUserId is null) return Array.Empty<CursorDailySpendRow>();

        using var data = await PostJsonAsync(
            "https://cursor.com/api/dashboard/get-daily-spend-by-category", headers,
            new Dictionary<string, object>
            {
                ["teamId"] = teamId,
                ["userId"] = dashboardUserId.Value,
                ["periodStartMs"] = startMs,
                ["periodEndMs"] = endMs,
                ["groupBy"] = 1,
                ["spendType"] = 1,
            },
            cancellationToken).ConfigureAwait(false);
        if (data is null) return Array.Empty<CursorDailySpendRow>();
        var rows = GetArray(data.RootElement, "dailySpend");
        var list = new List<CursorDailySpendRow>();
        foreach (var row in rows)
        {
            var day = ToDouble(GetValue(row, "day"));
            var category = GetString(row, "category");
            var spend = ToInt(GetValue(row, "spendCents"));
            var tokens = ToInt(GetValue(row, "totalTokens"));
            if (day is null || category is null || spend is null || tokens is null) continue;
            list.Add(new CursorDailySpendRow(day.Value, category, spend.Value, tokens.Value));
        }
        return list;
    }

    private static async Task<int?> ResolveDashboardUserIdAsync(
        CursorAuth auth,
        IReadOnlyDictionary<string, string> headers,
        (string UserId, bool IsTeam, int? TeamId, int RequestLimit, bool OnDemand, string? Plan) setup,
        CancellationToken cancellationToken)
    {
        if (int.TryParse(auth.UserId, NumberStyles.Integer, CultureInfo.InvariantCulture, out var numeric)) return numeric;
        if (!setup.IsTeam || setup.TeamId is not { } teamId) return null;
        using var data = await PostJsonAsync(
            "https://cursor.com/api/dashboard/get-team-spend", headers,
            new { teamId },
            cancellationToken).ConfigureAwait(false);
        if (data is null) return null;
        var members = GetArray(data.RootElement, "teamMemberSpend");
        foreach (var member in members)
        {
            if (string.Equals(GetString(member, "email"), auth.Email, StringComparison.OrdinalIgnoreCase))
            {
                if (ToInt(GetValue(member, "userId")) is { } uid) return uid;
            }
        }
        return null;
    }

    private static string? MemberUserIdString(JsonElement member)
    {
        var s = GetString(member, "userId");
        if (!string.IsNullOrEmpty(s)) return s;
        return ToInt(GetValue(member, "userId"))?.ToString(CultureInfo.InvariantCulture);
    }

    public static UsageSnapshot Empty(ProviderKind provider, bool installed, string error) =>
        new(provider, installed, [], error == "not_logged_in" ? Localizer.Get("notLoggedIn") : Localizer.Get("unavailable"),
            $"Cursor — {(error == "not_logged_in" ? Localizer.Get("notLoggedIn") : Localizer.Get("unavailable"))}", null, null, error);

    private static CursorAuth? LoadAuth()
    {
        lock (CacheGate)
        {
            if (_authCache is { } cached && DateTimeOffset.UtcNow - cached.At < TimeSpan.FromSeconds(10)) return cached.Auth;
        }

        var path = ProviderAvailability.CursorDatabasePath;
        if (!File.Exists(path)) return null;
        var connectionString = new SqliteConnectionStringBuilder { DataSource = path, Mode = SqliteOpenMode.ReadOnly, Cache = SqliteCacheMode.Shared };
        using var db = new SqliteConnection(connectionString.ToString());
        db.Open();
        using var command = db.CreateCommand();
        command.CommandText = "SELECT key, value FROM ItemTable WHERE key IN ('cursorAuth/accessToken', 'cursorAuth/cachedEmail')";
        using var reader = command.ExecuteReader();
        string? token = null;
        string? email = null;
        while (reader.Read())
        {
            var key = reader.GetString(0);
            var value = reader.GetValue(1) switch
            {
                byte[] bytes => Encoding.UTF8.GetString(bytes),
                string text => text,
                _ => reader.GetValue(1).ToString(),
            };
            if (key == "cursorAuth/accessToken") token = value;
            if (key == "cursorAuth/cachedEmail") email = value;
        }
        if (string.IsNullOrWhiteSpace(token)) return null;
        var jwt = CursorSafeStorage.ResolveAccessToken(token);
        if (string.IsNullOrWhiteSpace(jwt)) return null;
        var userId = ParseUserId(jwt);
        if (userId is null) return null;
        var auth = new CursorAuth(userId, $"{userId}%3A%3A{jwt}", email, jwt);
        lock (CacheGate) _authCache = (auth, DateTimeOffset.UtcNow);
        return auth;
    }

    private static string? ParseUserId(string jwt)
    {
        var pieces = jwt.Split('.');
        if (pieces.Length < 2) return null;
        try
        {
            var payload = pieces[1].Replace('-', '+').Replace('_', '/');
            payload = payload.PadRight(payload.Length + (4 - payload.Length % 4) % 4, '=');
            using var doc = JsonDocument.Parse(Convert.FromBase64String(payload));
            var subject = GetString(doc.RootElement, "sub");
            return subject?.Split('|').LastOrDefault();
        }
        catch { return null; }
    }

    private static async Task<(string UserId, bool IsTeam, int? TeamId, int RequestLimit, bool OnDemand, string? Plan)?> EnsureSetupAsync(CursorAuth auth, CancellationToken cancellationToken)
    {
        lock (CacheGate)
        {
            if (_setupCache is { } setup && setup.UserId == auth.UserId && DateTimeOffset.UtcNow - setup.At < TimeSpan.FromMinutes(5))
                return (setup.UserId, setup.IsTeam, setup.TeamId, setup.RequestLimit, setup.OnDemand, setup.Plan);
        }

        using var stripe = await GetJsonAsync("https://cursor.com/api/auth/stripe", CursorHeaders(auth.SessionToken), cancellationToken).ConfigureAwait(false);
        using var usage = await GetJsonAsync($"https://cursor.com/api/usage?user={Uri.EscapeDataString(auth.UserId)}", CursorHeaders(auth.SessionToken), cancellationToken).ConfigureAwait(false);
        if (stripe is null || usage is null) return null;
        var stripeRoot = stripe.RootElement;
        var usageRoot = usage.RootElement;
        var membership = GetString(stripeRoot, "individualMembershipType")
            ?? GetString(stripeRoot, "membershipType")
            ?? GetString(stripeRoot, "teamMembershipType");
        var totals = ExtractUsageTotals(usageRoot);
        var teamValue = ToInt(GetValue(stripeRoot, "teamId"));
        (string UserId, bool IsTeam, int? TeamId, int RequestLimit, bool OnDemand, string? Plan) result = (
            auth.UserId,
            GetBool(stripeRoot, "isTeamMember") && teamValue is not null,
            teamValue,
            totals.Limit > 0 ? totals.Limit : totals.Used,
            GetBool(stripeRoot, "isOnBillableAuto"),
            FormatPlanName(membership));
        lock (CacheGate) _setupCache = (
            result.UserId, result.IsTeam, result.TeamId, result.RequestLimit, result.OnDemand, result.Plan, DateTimeOffset.UtcNow);
        return result;
    }

    private static Dictionary<string, string> CursorHeaders(string token) => new()
    {
        ["Cookie"] = $"WorkosCursorSessionToken={token}",
        ["Origin"] = "https://cursor.com",
        ["Referer"] = "https://cursor.com/dashboard",
    };

    private static Dictionary<string, string> CursorJsonHeaders(string token)
    {
        var h = CursorHeaders(token);
        h["Content-Type"] = "application/json";
        return h;
    }

    private static async Task<JsonDocument?> GetJsonAsync(string url, IReadOnlyDictionary<string, string> headers, CancellationToken cancellationToken)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, url);
        foreach (var header in headers) request.Headers.TryAddWithoutValidation(header.Key, header.Value);
        return await SendJsonAsync(request, cancellationToken).ConfigureAwait(false);
    }

    private static async Task<JsonDocument?> PostJsonAsync(string url, IReadOnlyDictionary<string, string> headers, object body, CancellationToken cancellationToken)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, url) { Content = JsonContent.Create(body) };
        foreach (var header in headers) request.Headers.TryAddWithoutValidation(header.Key, header.Value);
        return await SendJsonAsync(request, cancellationToken).ConfigureAwait(false);
    }

    private static async Task<JsonDocument?> SendJsonAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        try
        {
            using var response = await Http.SendAsync(request, cancellationToken).ConfigureAwait(false);
            if (!response.IsSuccessStatusCode) return null;
            await using var stream = await response.Content.ReadAsStreamAsync(cancellationToken).ConfigureAwait(false);
            return await JsonDocument.ParseAsync(stream, cancellationToken: cancellationToken).ConfigureAwait(false);
        }
        catch { return null; }
    }

    private static (int Used, int Limit) ExtractUsageTotals(JsonElement usage)
    {
        var gpt4 = GetValue(usage, "gpt-4");
        if (TryBucketTotals(gpt4, out var preferred)) return preferred;
        var best = (Used: 0, Limit: 0);
        foreach (var property in usage.EnumerateObject())
            if (property.Name != "gpt-4" && TryBucketTotals(property.Value, out var totals)
                && (totals.Limit > best.Limit || totals.Limit == best.Limit && totals.Used > best.Used)) best = totals;
        return best;
    }

    private static bool TryBucketTotals(JsonElement bucket, out (int Used, int Limit) totals)
    {
        var used = FirstInt(bucket, "numRequests", "usedRequests", "requestsUsed", "includedRequestsUsed");
        var limit = FirstInt(bucket, "maxRequestUsage", "maxRequests", "requestLimit", "includedRequestLimit");
        totals = (used ?? 0, limit ?? 0);
        return used is not null || limit is not null;
    }

    private static int? FirstInt(JsonElement value, params string[] keys)
    {
        foreach (var key in keys)
            if (ToInt(GetValue(value, key)) is { } result) return result;
        return null;
    }

    private static string? FormatPlanName(string? raw)
    {
        if (string.IsNullOrWhiteSpace(raw)) return null;
        var key = raw.Trim().ToLowerInvariant();
        return key switch
        {
            "ultra" => "Ultra", "pro" => "Pro", "pro_plus" or "proplus" or "pro+" => "Pro+",
            "plus" => "Plus", "business" => "Business", "enterprise" => "Enterprise",
            "team" => "Team", "free" => "Free", "hobby" => "Hobby",
            _ => string.Join(' ', key.Split(['_', ' ', '-'], StringSplitOptions.RemoveEmptyEntries)
                .Select(s => char.ToUpperInvariant(s[0]) + s[1..])),
        };
    }

    private static double? ClampPercent(double? value) => value is null ? null : Math.Clamp(value.Value, 0, 100);
    private static DateTimeOffset? ParseDate(string? value) => DateTimeOffset.TryParse(value, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal, out var date) ? date : null;
    private static JsonElement GetValue(JsonElement value, string key) => value.ValueKind == JsonValueKind.Object && value.TryGetProperty(key, out var result) ? result : default;
    private static string? GetString(JsonElement value, string key) => GetValue(value, key).ValueKind == JsonValueKind.String ? GetValue(value, key).GetString() : null;
    private static double? ToDouble(JsonElement value) => value.ValueKind switch
    {
        JsonValueKind.Number when value.TryGetDouble(out var numberValue) => numberValue,
        JsonValueKind.String when double.TryParse(value.GetString(), NumberStyles.Any, CultureInfo.InvariantCulture, out var stringValue) => stringValue,
        _ => null,
    };
    private static int? ToInt(JsonElement value) => value.ValueKind switch
    {
        JsonValueKind.Number when value.TryGetInt32(out var numberValue) => numberValue,
        JsonValueKind.String when int.TryParse(value.GetString(), NumberStyles.Integer, CultureInfo.InvariantCulture, out var stringValue) => stringValue,
        _ => null,
    };
    private static bool GetBool(JsonElement value, string key) => GetValue(value, key).ValueKind == JsonValueKind.True;
    private static JsonElement[] GetArray(JsonElement value, string key) => GetValue(value, key).ValueKind == JsonValueKind.Array ? GetValue(value, key).EnumerateArray().ToArray() : [];
}

internal static class CodexUsageClient
{
    private static readonly TimeSpan Timeout = TimeSpan.FromSeconds(15);

    public static async Task<UsageSnapshot> FetchAsync(CancellationToken cancellationToken)
    {
        var installed = ProviderAvailability.IsCodexInstalled;
        var command = ProviderAvailability.FindCodexCommand();
        if (command is null) return Empty(installed, "no_codex_cli");

        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(Timeout);
        Process? process = null;
        try
        {
            process = new Process { StartInfo = CreateStartInfo(command) };
            if (!process.Start()) return Empty(installed, "spawn_failed");
            _ = process.StandardError.ReadToEndAsync(timeout.Token);
            await process.StandardInput.WriteLineAsync("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2024-11-05\",\"capabilities\":{},\"clientInfo\":{\"name\":\"ai-usage\",\"version\":\"1.0.0\"}}}").ConfigureAwait(false);
            await process.StandardInput.FlushAsync(timeout.Token).ConfigureAwait(false);
            var initialized = await ReadResponseAsync(process.StandardOutput, 1, timeout.Token).ConfigureAwait(false);
            if (initialized is null) return Empty(installed, "not_initialized");

            await process.StandardInput.WriteLineAsync("{\"jsonrpc\":\"2.0\",\"method\":\"initialized\",\"params\":{}}").ConfigureAwait(false);
            await process.StandardInput.WriteLineAsync("{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"account/rateLimits/read\",\"params\":{}}").ConfigureAwait(false);
            await process.StandardInput.FlushAsync(timeout.Token).ConfigureAwait(false);
            var response = await ReadResponseAsync(process.StandardOutput, 2, timeout.Token).ConfigureAwait(false);
            process.StandardInput.Close();
            if (!process.HasExited) process.Kill(true);
            if (response is null) return Empty(installed, "no_rate_limits");
            return ParseRateLimits(response.Value, installed);
        }
        catch (OperationCanceledException) { return Empty(installed, "timeout"); }
        catch { return Empty(installed, "unavailable"); }
        finally
        {
            if (process is not null)
            {
                try { if (!process.HasExited) process.Kill(true); }
                catch { }
                process.Dispose();
            }
        }
    }

    private static ProcessStartInfo CreateStartInfo(string command)
    {
        var start = new ProcessStartInfo
        {
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
        };
        if (command.EndsWith(".cmd", StringComparison.OrdinalIgnoreCase) || command.EndsWith(".bat", StringComparison.OrdinalIgnoreCase))
        {
            start.FileName = "cmd.exe";
            start.ArgumentList.Add("/d");
            start.ArgumentList.Add("/s");
            start.ArgumentList.Add("/c");
            start.ArgumentList.Add($"\"\"{command}\" -s read-only -a never app-server\"");
        }
        else
        {
            start.FileName = command;
            start.ArgumentList.Add("-s");
            start.ArgumentList.Add("read-only");
            start.ArgumentList.Add("-a");
            start.ArgumentList.Add("never");
            start.ArgumentList.Add("app-server");
        }
        return start;
    }

    private static async Task<JsonElement?> ReadResponseAsync(StreamReader reader, int id, CancellationToken cancellationToken)
    {
        var buffer = new StringBuilder();
        var scratch = new char[4096];
        while (!cancellationToken.IsCancellationRequested)
        {
            var read = await reader.ReadAsync(scratch, cancellationToken).ConfigureAwait(false);
            if (read == 0)
            {
                if (buffer.Length == 0) return null;
                await Task.Delay(30, cancellationToken).ConfigureAwait(false);
                continue;
            }

            buffer.Append(scratch, 0, read);
            while (TryTakeJsonLine(buffer, out var line))
            {
                if (string.IsNullOrWhiteSpace(line)) continue;
                try
                {
                    using var document = JsonDocument.Parse(line);
                    var root = document.RootElement;
                    if (root.TryGetProperty("id", out var responseId)
                        && responseId.ValueKind == JsonValueKind.Number
                        && responseId.GetInt32() == id)
                        return root.Clone();
                }
                catch (JsonException) { }
            }
        }
        return null;
    }

    private static bool TryTakeJsonLine(StringBuilder buffer, out string line)
    {
        var text = buffer.ToString();
        var newline = text.IndexOf('\n');
        if (newline < 0)
        {
            line = "";
            return false;
        }

        line = text[..newline].Trim('\r', '\n', ' ');
        buffer.Clear();
        if (newline + 1 < text.Length) buffer.Append(text[(newline + 1)..]);
        return true;
    }

    private static UsageSnapshot ParseRateLimits(JsonElement response, bool installed)
    {
        if (!response.TryGetProperty("result", out var result) || !result.TryGetProperty("rateLimits", out var limits))
            return Empty(installed, "parse_failed");

        var windows = new List<UsageWindow>();
        var primary = GetValue(limits, "primary");
        var secondary = GetValue(limits, "secondary");
        if (ToDouble(GetValue(primary, "usedPercent")) is { } primaryUsed)
            windows.Add(new UsageWindow(Localizer.Get("claudeFiveHour"), Math.Clamp(100 - primaryUsed, 0, 100), UnixDate(GetValue(primary, "resetsAt"))));
        if (ToDouble(GetValue(secondary, "usedPercent")) is { } weeklyUsed)
            windows.Add(new UsageWindow(Localizer.Get("weekly"), Math.Clamp(100 - weeklyUsed, 0, 100), UnixDate(GetValue(secondary, "resetsAt"))));

        if (windows.Count == 0) return Empty(installed, "no_rate_limits");
        var plan = GetString(limits, "planType");
        var compactParts = new List<string>();
        if (windows.Count > 0) compactParts.Add(windows[0].CompactText("clock"));
        if (windows.Count > 1) compactParts.Add(windows[1].CompactText("day"));
        var compact = string.Join(" / ", compactParts);
        var planName = FormatPlan(plan);
        var labels = windows.Select((window, index) => $"{window.Label} {window.PercentText} ({(index == 0 ? window.ResetsAt?.ToLocalTime().ToString("H:mm") : window.ResetsAt?.ToLocalTime().ToString("M/d")) ?? "—"})");
        var resetCredits = GetValue(result, "rateLimitResetCredits");
        var credits = ToInt(GetValue(resetCredits, "availableCount"));
        var menu = $"ChatGPT - {(planName is null ? "" : planName + " ")}{string.Join(" / ", labels)}";
        if (credits is > 0) menu += $" / {Localizer.Get("resetCredits", credits.Value)}";
        return new UsageSnapshot(ProviderKind.Codex, installed, windows, compact, menu, planName,
            windows.Min(window => window.RemainingPercent));
    }

    private static UsageSnapshot Empty(bool installed, string error) => new(
        ProviderKind.Codex, installed, [], Localizer.Get("unavailable"), $"ChatGPT — {Localizer.Get("unavailable")}", null, null, error);

    private static string? FormatPlan(string? raw) => string.IsNullOrWhiteSpace(raw) ? null : raw.Trim().ToLowerInvariant() switch
    {
        "plus" => "Plus", "pro" => "Pro", "team" => "Team", "business" => "Business", "enterprise" => "Enterprise", "free" => "Free",
        _ => CultureInfo.InvariantCulture.TextInfo.ToTitleCase(raw.Replace('_', ' ')),
    };

    private static DateTimeOffset? UnixDate(JsonElement value) => ToDouble(value) is { } seconds
        ? DateTimeOffset.FromUnixTimeSeconds((long)seconds) : null;
    private static JsonElement GetValue(JsonElement value, string key) => value.ValueKind == JsonValueKind.Object && value.TryGetProperty(key, out var result) ? result : default;
    private static string? GetString(JsonElement value, string key) => GetValue(value, key).ValueKind == JsonValueKind.String ? GetValue(value, key).GetString() : null;
    private static double? ToDouble(JsonElement value) => value.ValueKind switch
    {
        JsonValueKind.Number when value.TryGetDouble(out var numberValue) => numberValue,
        JsonValueKind.String when double.TryParse(value.GetString(), NumberStyles.Any, CultureInfo.InvariantCulture, out var stringValue) => stringValue,
        _ => null,
    };
    private static int? ToInt(JsonElement value) => value.ValueKind switch
    {
        JsonValueKind.Number when value.TryGetInt32(out var numberValue) => numberValue,
        JsonValueKind.String when int.TryParse(value.GetString(), NumberStyles.Integer, CultureInfo.InvariantCulture, out var stringValue) => stringValue,
        _ => null,
    };
}

internal static class ClaudeUsageClient
{
    public static void ConsumeStatusLineInput()
    {
        try
        {
            var input = Console.In.ReadToEnd();
            using var document = JsonDocument.Parse(input);
            var limits = GetValue(document.RootElement, "rate_limits");
            var output = new Dictionary<string, object> { ["fetchedAt"] = DateTimeOffset.UtcNow.ToUnixTimeSeconds() };
            CopyWindow(limits, "five_hour", output);
            CopyWindow(limits, "seven_day", output);
            if (output.Count <= 1) return;
            Directory.CreateDirectory(ProviderAvailability.ClaudeDirectory);
            var temp = ProviderAvailability.ClaudeSnapshotPath + ".tmp";
            File.WriteAllText(temp, JsonSerializer.Serialize(output));
            File.Move(temp, ProviderAvailability.ClaudeSnapshotPath, true);
        }
        catch { }
    }

    public static void InstallStatusLineIfAvailable(string executablePath)
    {
        var settingsPath = Path.Combine(ProviderAvailability.ClaudeDirectory, "settings.json");
        var hasClaudeState = File.Exists(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".claude.json"))
            || File.Exists(Path.Combine(ProviderAvailability.ClaudeDirectory, ".credentials.json"))
            || ProviderAvailability.FindExecutable("claude") is not null;
        if (!hasClaudeState) return;

        try
        {
            JsonObject settings;
            if (File.Exists(settingsPath))
                settings = JsonNode.Parse(File.ReadAllText(settingsPath)) as JsonObject ?? new JsonObject();
            else settings = new JsonObject();
            if (settings.ContainsKey("statusLine")) return;

            Directory.CreateDirectory(ProviderAvailability.ClaudeDirectory);
            var helperPath = Path.Combine(ProviderAvailability.ClaudeDirectory, "ai-usage-statusline.ps1");
            var appPathForPowerShell = executablePath.Replace("'", "''").Replace('\\', '/');
            var helper = "$payload = [Console]::In.ReadToEnd()\r\n"
                + "if (-not [string]::IsNullOrWhiteSpace($payload)) {\r\n"
                + $"  $payload | & '{appPathForPowerShell}' --claude-statusline | Out-Null\r\n"
                + "}\r\n";
            File.WriteAllText(helperPath, helper, new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));
            var helperPathForCommand = helperPath.Replace('\\', '/');
            settings["statusLine"] = new JsonObject
            {
                ["type"] = "command",
                ["command"] = $"powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File \"{helperPathForCommand}\"",
                ["refreshInterval"] = 30,
            };
            File.WriteAllText(settingsPath, settings.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
        }
        catch { }
    }

    public static Task<UsageSnapshot> ReadStatusLineSnapshotAsync(CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var installed = ProviderAvailability.IsClaudeInstalled;
        try
        {
            if (!File.Exists(ProviderAvailability.ClaudeSnapshotPath))
                return Task.FromResult(new UsageSnapshot(ProviderKind.Claude, installed, [], Localizer.Get("loading"), "Claude —", null, null, "awaiting_statusline"));
            using var document = JsonDocument.Parse(File.ReadAllText(ProviderAvailability.ClaudeSnapshotPath));
            var root = document.RootElement;
            var windows = new List<UsageWindow>();
            AddWindow(root, "five_hour", Localizer.Get("claudeFiveHour"), windows);
            AddWindow(root, "seven_day", Localizer.Get("weekly"), windows);
            if (windows.Count == 0)
                return Task.FromResult(new UsageSnapshot(ProviderKind.Claude, installed, [], Localizer.Get("loading"), "Claude —", null, null, "awaiting_statusline"));
            var compact = string.Join(" / ", windows.Select((window, index) => window.CompactText(index == 0 ? "clock" : "day")));
            var details = string.Join(" / ", windows.Select(w => $"{w.Label} {w.PercentText} ({w.ResetsAt?.ToLocalTime().ToString("H:mm") ?? "—"})"));
            return Task.FromResult(new UsageSnapshot(ProviderKind.Claude, installed, windows, compact, $"Claude - {details}", null,
                windows.Min(window => window.RemainingPercent)));
        }
        catch
        {
            return Task.FromResult(new UsageSnapshot(ProviderKind.Claude, installed, [], Localizer.Get("unavailable"), "Claude —", null, null, "snapshot_failed"));
        }
    }

    private static void CopyWindow(JsonElement limits, string key, IDictionary<string, object> output)
    {
        var window = GetValue(limits, key);
        if (window.ValueKind != JsonValueKind.Object) return;
        if (ToDouble(GetValue(window, "used_percentage")) is { } used) output[$"{key}UsedPercent"] = used;
        var reset = GetValue(window, "resets_at");
        if (ToDouble(reset) is { } unix) output[$"{key}ResetsAt"] = unix;
        else if (reset.ValueKind == JsonValueKind.String && DateTimeOffset.TryParse(reset.GetString(), CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal, out var date))
            output[$"{key}ResetsAt"] = date.ToUnixTimeSeconds();
    }

    private static void AddWindow(JsonElement root, string prefix, string label, ICollection<UsageWindow> windows)
    {
        var usedKey = prefix + "UsedPercent";
        if (!root.TryGetProperty(usedKey, out var usedValue) || ToDouble(usedValue) is not { } used) return;
        DateTimeOffset? reset = null;
        if (ToDouble(GetValue(root, prefix + "ResetsAt")) is { } unix) reset = DateTimeOffset.FromUnixTimeSeconds((long)unix);
        windows.Add(new UsageWindow(label, Math.Clamp(100 - used, 0, 100), reset));
    }

    private static JsonElement GetValue(JsonElement value, string key) => value.ValueKind == JsonValueKind.Object && value.TryGetProperty(key, out var result) ? result : default;
    private static double? ToDouble(JsonElement value) => value.ValueKind switch
    {
        JsonValueKind.Number when value.TryGetDouble(out var numberValue) => numberValue,
        JsonValueKind.String when double.TryParse(value.GetString(), NumberStyles.Any, CultureInfo.InvariantCulture, out var stringValue) => stringValue,
        _ => null,
    };
}

internal static class CurrencyService
{
    private static readonly Dictionary<string, string> Codes = new() { ["eur"] = "EUR", ["jpy"] = "JPY", ["gbp"] = "GBP", ["cny"] = "CNY" };
    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(10) };

    public static async Task<double?> GetRateAsync(string currency, CancellationToken cancellationToken = default)
    {
        if (currency == "usd") return 1;
        if (!Codes.TryGetValue(currency, out var code)) return null;
        var cached = Settings.GetRate(code);
        if (cached is not null && DateTimeOffset.UtcNow - cached.FetchedAt < TimeSpan.FromHours(6)) return cached.Rate;
        try
        {
            using var response = await Http.GetAsync($"https://api.frankfurter.app/latest?from=USD&to={code}", cancellationToken).ConfigureAwait(false);
            response.EnsureSuccessStatusCode();
            using var doc = await JsonDocument.ParseAsync(await response.Content.ReadAsStreamAsync(cancellationToken), cancellationToken: cancellationToken).ConfigureAwait(false);
            if (doc.RootElement.TryGetProperty("rates", out var rates) && rates.TryGetProperty(code, out var value) && value.TryGetDouble(out var rate))
            {
                Settings.SetRate(code, rate);
                return rate;
            }
        }
        catch { }
        return cached?.Rate;
    }

    public static string FormatOnDemand(double dollars, double? rate, string currency)
    {
        if (currency == "usd" || rate is null) return $"${dollars:0.00}";
        var amount = dollars * rate.Value;
        return currency switch
        {
            "jpy" => $"¥{Math.Round(amount):0}",
            "cny" => $"{Math.Round(amount):0}元",
            "eur" => $"€{amount:0.00}",
            "gbp" => $"£{amount:0.00}",
            _ => $"${dollars:0.00}",
        };
    }
}
