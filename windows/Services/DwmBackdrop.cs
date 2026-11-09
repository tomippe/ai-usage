using System.Runtime.InteropServices;
using Microsoft.Win32;

namespace AIUsage.Windows.Services;

/// <summary>
/// Windows 11 22H2+ の DWM システムバックドロップ。設定の「透明効果」がオフのときは使わない。
/// WPF でクライアントを透明にするには、フルクライアントへの <see cref="DwmExtendFrameIntoClientArea"/> が必要になりやすい。
/// </summary>
/// <remarks>
/// <see cref="DWM_SYSTEMBACKDROP_TYPE"/> の値は MSDN 通り（誤った数値だと属性が無視され、CompositionTarget だけ透明にすると真っ黒になる）。
/// </remarks>
internal static class DwmBackdrop
{
    private const int DWMWA_USE_IMMERSIVE_DARK_MODE = 20;
    private const int DWMWA_SYSTEMBACKDROP_TYPE = 38;
    /// <summary>Win11: ウィンドウ外形を角丸に（内側の Border.CornerRadius だけだと「真四角の窓＋角丸パネル」の二重に見える）</summary>
    private const int DWMWA_WINDOW_CORNER_PREFERENCE = 33;

    private const int DWMWCP_DEFAULT = 0;
    private const int DWMWCP_ROUNDSMALL = 3;

    private const int MinBuildForRoundedCorners = 22000;

    // https://learn.microsoft.com/en-us/windows/win32/api/dwmapi/ne-dwmapi-dwm_systembackdrop_type
    private const int DWMSBT_AUTO = 0;
    private const int DWMSBT_NONE = 1;
    private const int DWMSBT_MAINWINDOW = 2;
    private const int DWMSBT_TRANSIENTWINDOW = 3;

    /// <summary>22621 = Windows 11 22H2（DWMWA_SYSTEMBACKDROP_TYPE が使える）</summary>
    private const int MinBuildForSystemBackdrop = 22621;

    /// <summary>設定 → パーソナル設定 → 色 → 透明効果。0 のときシステムバックドロップは期待できない。</summary>
    public static bool IsOsTransparencyEnabled()
    {
        using var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
        return key?.GetValue("EnableTransparency") switch
        {
            int i => i != 0,
            _ => true,
        };
    }

    /// <summary>
    /// トップに短い帯向け: デスクトップアクリル（TRANSIENT）→ だめなら Mica（MAIN）→ AUTO。
    /// Set が S_OK でも WPF では合成されず真っ黒になることがあるため、設定後に <see cref="DwmGetWindowAttribute"/> で実値を確認する。
    /// </summary>
    public static bool TryApplyTaskbarLikeBackdrop(nint hwnd, bool shellUsesLightTheme)
    {
        if (hwnd == 0) return false;
        if (Environment.OSVersion.Version.Build < MinBuildForSystemBackdrop) return false;
        if (!IsOsTransparencyEnabled()) return false;

        var darkMode = shellUsesLightTheme ? 0 : 1;
        _ = DwmSetWindowAttribute(hwnd, DWMWA_USE_IMMERSIVE_DARK_MODE, ref darkMode, sizeof(int));

        // ボーダーレス WPF で背後合成をクライアント全域に広げる
        var margins = new MARGINS { cxLeftWidth = -1, cxRightWidth = -1, cyTopHeight = -1, cyBottomHeight = -1 };
        _ = DwmExtendFrameIntoClientArea(hwnd, ref margins);

        ReadOnlySpan<int> candidates = [DWMSBT_TRANSIENTWINDOW, DWMSBT_MAINWINDOW, DWMSBT_AUTO];
        foreach (var backdropType in candidates)
        {
            var t = backdropType;
            if (DwmSetWindowAttribute(hwnd, DWMWA_SYSTEMBACKDROP_TYPE, ref t, sizeof(int)) != 0)
                continue;
            if (TryVerifySystemBackdrop(hwnd))
                return true;
        }

        ClearBackdropAndExtendedFrame(hwnd);
        return false;
    }

    /// <summary>実際に NONE 以外のシステムバックドロップが有効か（AUTO は DWM に任せるので有効とみなす）</summary>
    private static bool TryVerifySystemBackdrop(nint hwnd)
    {
        if (DwmGetWindowAttribute(hwnd, DWMWA_SYSTEMBACKDROP_TYPE, out var value, sizeof(int)) != 0)
            return false;
        return value is not DWMSBT_NONE;
    }

    private static void ClearBackdropAndExtendedFrame(nint hwnd)
    {
        var none = DWMSBT_NONE;
        _ = DwmSetWindowAttribute(hwnd, DWMWA_SYSTEMBACKDROP_TYPE, ref none, sizeof(int));
        var zero = new MARGINS();
        _ = DwmExtendFrameIntoClientArea(hwnd, ref zero);
    }

    [DllImport("dwmapi.dll", PreserveSig = true)]
    private static extern int DwmSetWindowAttribute(nint hwnd, int dwAttribute, ref int pvAttribute, int cbAttribute);

    [DllImport("dwmapi.dll", PreserveSig = true)]
    private static extern int DwmGetWindowAttribute(nint hwnd, int dwAttribute, out int pvAttribute, int cbAttribute);

    [DllImport("dwmapi.dll", PreserveSig = true)]
    private static extern int DwmExtendFrameIntoClientArea(nint hwnd, ref MARGINS margins);

    [StructLayout(LayoutKind.Sequential)]
    private struct MARGINS
    {
        public int cxLeftWidth;
        public int cxRightWidth;
        public int cyTopHeight;
        public int cyBottomHeight;
    }

    internal static bool IsSystemBackdropSupported() =>
        Environment.OSVersion.Version.Build >= MinBuildForSystemBackdrop;

    /// <summary>
    /// ボーダーレス WPF で内側だけ CornerRadius すると長方形の HWND と二重になる。Win11 では DWM に外形角丸を任せる。
    /// </summary>
    public static bool TrySetSmallRoundedWindowCorners(nint hwnd)
    {
        if (hwnd == 0) return false;
        if (Environment.OSVersion.Version.Build < MinBuildForRoundedCorners) return false;
        var pref = DWMWCP_ROUNDSMALL;
        return DwmSetWindowAttribute(hwnd, DWMWA_WINDOW_CORNER_PREFERENCE, ref pref, sizeof(int)) == 0;
    }
}
