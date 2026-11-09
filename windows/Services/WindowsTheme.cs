using System.Windows;
using System.Windows.Media;
using Microsoft.Win32;

namespace AIUsage.Windows.Services;

internal static class WindowsTheme
{
    /// <summary>前回適用時と同じか比較用（タスクバー／シェルのライト／ダーク）</summary>
    private static bool? _lastShellLight;

    /// <summary>レジストリ: 設定 → 個人用設定 → 色 の「モード」で、アプリウィンドウ用（タスクバーとは別キー）。</summary>
    public static bool IsLightAppsTheme() => ReadPersonalizeDword("AppsUseLightTheme") is not 0;

    /// <summary>
    /// タスクバー・スタート・通知エリアなどシェル UI と同じキー。
    /// 未設定の古い OS では <see cref="IsLightAppsTheme"/> にフォールバック。
    /// </summary>
    public static bool IsLightTaskbarShellTheme()
    {
        var system = ReadPersonalizeDword("SystemUsesLightTheme");
        if (system is not null) return system != 0;
        return IsLightAppsTheme();
    }

    private static int? ReadPersonalizeDword(string name)
    {
        using var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
        return key?.GetValue(name) switch
        {
            int i => i,
            _ => null,
        };
    }

    public static void Apply(Application app, bool? light = null)
    {
        var isLight = light ?? IsLightTaskbarShellTheme();
        _lastShellLight = isLight;

        // フローティング窓: Win11 DWM システムバックドロップ成功時は Window を Transparent + 薄いティント（下記 ApplyFloatingWindowBackdrop）。
        // 未対応 OS では不透明のまま（レイヤード＋透明だけだとクライアントが黒一色になりがち）。
        var panelSolid = new SolidColorBrush(isLight ? Color.FromRgb(0xF9, 0xF9, 0xF9) : Color.FromRgb(0x2C, 0x2C, 0x2C));
        app.Resources["PanelBrush"] = panelSolid;
        app.Resources["WindowChromeBrush"] = panelSolid;
        app.Resources["PanelSurfaceBrush"] = panelSolid;
        app.Resources["PanelBorderBrush"] = new SolidColorBrush(isLight ? Color.FromArgb(0x55, 0x00, 0x00, 0x00) : Color.FromArgb(0x45, 0xFF, 0xFF, 0xFF));
        app.Resources["ForegroundBrush"] = new SolidColorBrush(isLight ? Color.FromRgb(0x1A, 0x1A, 0x1A) : Color.FromRgb(0xF3, 0xF3, 0xF3));

        // Win11-ish context menu (WPF): acrylic-tinted fill + hairline border
        var menuBg = isLight ? Color.FromRgb(0xF3, 0xF3, 0xF3) : Color.FromRgb(0x2C, 0x2C, 0x2C);
        var menuBorder = isLight ? Color.FromArgb(0x44, 0x00, 0x00, 0x00) : Color.FromArgb(0x4C, 0xFF, 0xFF, 0xFF);
        app.Resources["ContextMenuBackgroundBrush"] = new SolidColorBrush(menuBg);
        app.Resources["ContextMenuBorderBrush"] = new SolidColorBrush(menuBorder);
    }

    public static bool RefreshIfChanged(Application app)
    {
        var isLight = IsLightTaskbarShellTheme();
        if (_lastShellLight is { } previous && previous == isLight) return false;
        Apply(app, isLight);
        return true;
    }

    public static Brush? MenuBackgroundBrush() => Application.Current?.TryFindResource("ContextMenuBackgroundBrush") as Brush;

    public static Brush MenuForegroundBrush() =>
        Application.Current?.TryFindResource("ForegroundBrush") as Brush ?? new SolidColorBrush(Colors.WhiteSmoke);

    public static Brush PanelBackgroundBrush() =>
        Application.Current?.TryFindResource("PanelBrush") as Brush ?? new SolidColorBrush(Color.FromRgb(0xF9, 0xF9, 0xF9));

    /// <summary>DWM アクリル背後用の極薄ティント（下がぼけて見えるようにアルファを抑える）</summary>
    public static SolidColorBrush PanelBackdropSurfaceBrush(bool isLight) =>
        new(isLight ? Color.FromArgb(0x99, 0xF9, 0xF9, 0xF9) : Color.FromArgb(0x99, 0x2C, 0x2C, 0x2C));

    public static Brush PanelHairlineBorderBrush() =>
        Application.Current?.TryFindResource("PanelBorderBrush") as SolidColorBrush ?? new SolidColorBrush(Color.FromArgb(0x55, 0, 0, 0));

    public static Brush ControlAccentBrush()
    {
        try { return SystemParameters.WindowGlassBrush; }
        catch { return new SolidColorBrush(Color.FromRgb(0, 120, 215)); }
    }
}
