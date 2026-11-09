using System.Globalization;

namespace AIUsage.Windows.Services;

internal static class CursorDashboardFormatter
{
    public static string FormatDashPercent(double? usedPercent)
    {
        if (usedPercent is null) return "—";
        return $"{Math.Round(usedPercent.Value, usedPercent.Value is >= 10 ? 0 : 1)}%";
    }

    public static string FormatDashTokens(int n)
    {
        var v = (double)n;
        if (v >= 1_000_000_000) return $"{v / 1_000_000_000:0.0}B";
        if (v >= 1_000_000) return $"{v / 1_000_000:0.0}M";
        if (v >= 1_000) return $"{v / 1_000:0.0}K";
        return n.ToString(CultureInfo.CurrentCulture);
    }

    /// <summary>チャート Y 軸（Mac formatChartAxisTokens）</summary>
    public static string FormatChartAxisTokens(int n)
    {
        if (n == 0) return "0";
        var v = (double)n;
        if (v >= 1_000_000_000)
        {
            var x = v / 1_000_000_000;
            return Math.Abs(x % 1) < 0.001 ? $"{x:0}B" : $"{x:0.0}B";
        }
        if (v >= 1_000_000)
        {
            var x = v / 1_000_000;
            return Math.Abs(x % 1) < 0.001 ? $"{x:0}M" : $"{x:0.0}M";
        }
        if (v >= 1_000)
        {
            var x = v / 1_000;
            return Math.Abs(x % 1) < 0.001 ? $"{x:0}K" : $"{x:0.1}K";
        }
        return n.ToString(CultureInfo.CurrentCulture);
    }

    public static string FormatSpendCents(int cents, double? rate, string currency)
    {
        var dollars = cents / 100.0;
        return CurrencyService.FormatOnDemand(dollars, rate, currency);
    }

    public static string FormatUsdSecondary(int cents) => $"${cents / 100.0:0.00}";
}
