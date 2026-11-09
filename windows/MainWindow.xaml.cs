using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Threading;
using AIUsage.Windows.Models;
using AIUsage.Windows.Services;

namespace AIUsage.Windows;

public partial class MainWindow : Window
{
    private readonly UsageService _usageService = new();
    private readonly UsageAlertMonitor _alertMonitor = new();
    private readonly WindowsUsageSpeechAnnouncer _speech = new();
    private readonly DispatcherTimer _refreshTimer = new() { Interval = TimeSpan.FromMinutes(1) };
    private readonly DispatcherTimer _claudeTimer = new() { Interval = TimeSpan.FromSeconds(15) };
    private readonly DispatcherTimer _foregroundTimer = new() { Interval = TimeSpan.FromMilliseconds(800) };
    private readonly Dictionary<ProviderKind, UsageSnapshot> _snapshots = [];
    private ProviderKind _displayProvider = Settings.LastProvider;
    private bool _fetching;
    private double? _exchangeRate;
    /// <summary>DWM システムバックドロップでクライアント透明化済み。<see cref="WindowsTheme.RefreshIfChanged"/> のあとに再適用する。</summary>
    private bool _floatingBackdropActive;
    public MainWindow()
    {
        InitializeComponent();
        // 先にテーマを載せないと、初回描画で Foreground が App.xaml 既定のままになり、黒背景に暗色文字になる
        WindowsTheme.Apply(Application.Current);
        ToolTip = Localizer.Get("tooltip");
        _refreshTimer.Tick += async (_, _) => await RefreshUsageAsync(force: false);
        _claudeTimer.Tick += async (_, _) => await RefreshClaudeStatusLineAsync();
        _foregroundTimer.Tick += (_, _) => UpdateForegroundProvider();
    }

    private void Window_SourceInitialized(object? sender, EventArgs e) =>
        TryApplyFloatingWindowBackdrop();

    private async void Window_Loaded(object sender, RoutedEventArgs e)
    {
        // Loaded で再度 Apply すると WindowChromeBrush が不透明に戻り、DWM 透過が効かなくなる
        TryApplyFloatingWindowBackdrop();
        RestorePosition();
        UpdateDisplay();
        _refreshTimer.Start();
        _claudeTimer.Start();
        _foregroundTimer.Start();
        await RefreshUsageAsync(force: true);
    }

    /// <summary>
    /// 壁紙が「ぬけて」見えるように DWM のシステムアクリルを試す。WPF の Transparent だけだとクライアントは真っ黒になりやすい。
    /// </summary>
    private void TryApplyFloatingWindowBackdrop()
    {
        var helper = new WindowInteropHelper(this);
        var hwnd = helper.Handle;
        if (hwnd == IntPtr.Zero) return;

        var isLight = WindowsTheme.IsLightTaskbarShellTheme();
        _ = DwmBackdrop.TrySetSmallRoundedWindowCorners(hwnd);
        var ok = DwmBackdrop.TryApplyTaskbarLikeBackdrop(hwnd, isLight);

        if (HwndSource.FromHwnd(hwnd) is { } src)
        {
            src.CompositionTarget.BackgroundColor = ok
                ? Colors.Transparent
                : Color.FromArgb(255, 255, 255, 255);
        }

        var app = Application.Current;
        if (app is null) return;

        if (ok)
        {
            _floatingBackdropActive = true;
            app.Resources["WindowChromeBrush"] = Brushes.Transparent;
            app.Resources["PanelSurfaceBrush"] = WindowsTheme.PanelBackdropSurfaceBrush(isLight);
        }
        else if (_floatingBackdropActive)
        {
            _floatingBackdropActive = false;
            WindowsTheme.Apply(app, isLight);
        }
    }

    private void Window_Closing(object? sender, System.ComponentModel.CancelEventArgs e)
    {
        Settings.SetWindowPosition(Left, Top);
        _refreshTimer.Stop();
        _claudeTimer.Stop();
        _foregroundTimer.Stop();
        _speech.Dispose();
    }

    private void RestorePosition()
    {
        var saved = Settings.WindowPosition;
        var area = SystemParameters.WorkArea;
        if (saved.Left is { } left && saved.Top is { } top
            && left >= area.Left - Width + 32 && left <= area.Right - 32
            && top >= area.Top - Height + 16 && top <= area.Bottom - 16)
        {
            Left = left;
            Top = top;
        }
        else
        {
            Left = Math.Max(area.Left, area.Right - Width - 24);
            Top = Math.Max(area.Top, area.Bottom - Height - 48);
        }
    }

    private async Task RefreshUsageAsync(bool force)
    {
        if (_fetching) return;
        if (!force && _snapshots.Values.Any(s => s.IsInstalled)
            && DateTimeOffset.UtcNow - _lastFullRefresh < TimeSpan.FromMinutes(1)) return;
        _fetching = true;
        UpdateDisplay();
        try
        {
            var refreshed = await _usageService.RefreshAllAsync();
            _snapshots.Clear();
            foreach (var snapshot in refreshed)
            {
                _snapshots[snapshot.Provider] = snapshot;
                ObserveUsageAlerts(snapshot);
            }
            _lastFullRefresh = DateTimeOffset.UtcNow;
            try { _exchangeRate = await CurrencyService.GetRateAsync(Settings.Currency, cancellationToken: default).ConfigureAwait(false); }
            catch { _exchangeRate = null; }
            if (!_snapshots.ContainsKey(_displayProvider)) _displayProvider = ChooseInitialProvider();
            UpdateDisplay();
        }
        catch
        {
            UsageText.Text = Localizer.Get("unavailable");
        }
        finally { _fetching = false; }
    }

    private DateTimeOffset _lastFullRefresh = DateTimeOffset.MinValue;

    private async Task RefreshClaudeStatusLineAsync()
    {
        if (!ProviderAvailability.IsClaudeInstalled) return;
        var snapshot = await _usageService.RefreshClaudeStatusLineAsync();
        _snapshots[snapshot.Provider] = snapshot;
        ObserveUsageAlerts(snapshot);
        UpdateDisplay();
    }

    private void ObserveUsageAlerts(UsageSnapshot snapshot)
    {
        if (snapshot.Provider == ProviderKind.Cursor)
        {
            var hasSplitUsage = snapshot.Windows.Any(w => w.Label == Localizer.Get("auto") || w.Label == Localizer.Get("api"));
            if (hasSplitUsage)
            {
                AnnounceIfCrossed(snapshot.Provider, "cursorNative", snapshot.Windows.FirstOrDefault(w => w.Label == Localizer.Get("auto"))?.RemainingPercent);
                AnnounceIfCrossed(snapshot.Provider, "cursorApi", snapshot.Windows.FirstOrDefault(w => w.Label == Localizer.Get("api"))?.RemainingPercent);
                AnnounceIfCrossed(snapshot.Provider, "standard", null);
            }
            else
            {
                AnnounceIfCrossed(snapshot.Provider, "cursorNative", null);
                AnnounceIfCrossed(snapshot.Provider, "cursorApi", null);
                AnnounceIfCrossed(snapshot.Provider, "standard", snapshot.RemainingPercent);
            }
            return;
        }

        AnnounceIfCrossed(snapshot.Provider, "fiveHour", snapshot.Windows.FirstOrDefault(w => w.Label == Localizer.Get("claudeFiveHour"))?.RemainingPercent);
        AnnounceIfCrossed(snapshot.Provider, "weekly", snapshot.Windows.FirstOrDefault(w => w.Label == Localizer.Get("weekly"))?.RemainingPercent);
    }

    private void AnnounceIfCrossed(ProviderKind provider, string window, double? remaining)
    {
        var threshold = _alertMonitor.Observe(provider, window, remaining);
        if (Settings.VoiceAlertsEnabled && threshold is { } alertThreshold)
            _speech.Announce(provider, window, alertThreshold);
    }

    private ProviderKind ChooseInitialProvider()
    {
        if (ProviderAvailability.InstalledProviders().Contains(Settings.LastProvider)) return Settings.LastProvider;
        return ProviderAvailability.InstalledProviders().FirstOrDefault();
    }

    private void UpdateForegroundProvider()
    {
        var themeChanged = WindowsTheme.RefreshIfChanged(Application.Current);
        if (themeChanged) ProviderAppIcon.ClearCache();
        TryApplyFloatingWindowBackdrop();
        var windowHandle = GetForegroundWindow();
        if (windowHandle == IntPtr.Zero) return;
        GetWindowThreadProcessId(windowHandle, out var processId);
        if (processId == 0 || (uint)Environment.ProcessId == processId) return;
        try
        {
            var processName = Process.GetProcessById((int)processId).ProcessName;
            ProviderKind? provider = processName.ToLowerInvariant() switch
            {
                "cursor" => ProviderKind.Cursor,
                "chatgpt" or "codex" or "chatgpt-desktop" => ProviderKind.Codex,
                _ => null,
            };
            if (provider is null || !ProviderAvailability.InstalledProviders().Contains(provider.Value)) return;
            if (_displayProvider == provider.Value) return;
            _displayProvider = provider.Value;
            Settings.LastProvider = provider.Value;
            UpdateDisplay();
        }
        catch { }
    }

    private void UpdateDisplay()
    {
        var installed = ProviderAvailability.InstalledProviders();
        if (installed.Count == 0)
        {
            ApplyProviderIcon(null, "AI");
            UsageText.Text = Localizer.Get("noProviders");
            return;
        }

        if (!installed.Contains(_displayProvider)) _displayProvider = ChooseInitialProvider();
        ApplyProviderIcon(ProviderAppIcon.GetIcon(_displayProvider), ProviderNames.Glyph(_displayProvider));
        if (_snapshots.TryGetValue(_displayProvider, out var snapshot))
        {
            if (snapshot.HasUsage) UsageText.Text = snapshot.CompactText;
            else if (snapshot.ErrorCode == "not_logged_in") UsageText.Text = Localizer.Get("notLoggedIn");
            else if (snapshot.ErrorCode == "awaiting_statusline") UsageText.Text = Localizer.Get("loading");
            else UsageText.Text = _fetching ? Localizer.Get("loading") : Localizer.Get("unavailable");
        }
        else
        {
            UsageText.Text = _fetching ? Localizer.Get("loading") : Localizer.Get("unavailable");
        }
    }

    private void ApplyProviderIcon(ImageSource? icon, string fallbackGlyph)
    {
        if (icon is not null)
        {
            ProviderIcon.Source = icon;
            ProviderIcon.Visibility = Visibility.Visible;
            ProviderGlyph.Visibility = Visibility.Collapsed;
            return;
        }

        ProviderIcon.Source = null;
        ProviderIcon.Visibility = Visibility.Collapsed;
        ProviderGlyph.Visibility = Visibility.Visible;
        ProviderGlyph.Text = fallbackGlyph;
    }

    private void Window_PreviewMouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        try { DragMove(); }
        catch (InvalidOperationException) { }
    }

    private void Window_PreviewMouseRightButtonUp(object sender, MouseButtonEventArgs e)
    {
        e.Handled = true;
        var menu = BuildContextMenu();
        menu.PlacementTarget = this;
        menu.Placement = System.Windows.Controls.Primitives.PlacementMode.MousePoint;
        menu.IsOpen = true;
    }

    private ContextMenu BuildContextMenu()
    {
        var menu = new ContextMenu();
        foreach (var snapshot in _snapshots.Values.Where(s => s.HasUsage).OrderBy(s => s.Provider))
        {
            MenuItem root;
            if (snapshot.Provider == ProviderKind.Cursor && snapshot.CursorDashboard is { } _)
            {
                // サブメニュー付き MenuItem はテンプレ側で矢印が 1 つ付く。手動の「▸」を足すと三角が二重になる。
                root = new MenuItem { Header = snapshot.MenuText, Tag = snapshot.Provider };
            }
            else root = new MenuItem { Header = snapshot.MenuText, Tag = snapshot.Provider };

            if (snapshot.Provider == ProviderKind.Cursor && snapshot.CursorDashboard is { } dashBundle)
            {
                var dashHost = new MenuItem
                {
                    StaysOpenOnClick = true,
                    Padding = new Thickness(0),
                    Focusable = false,
                    MinWidth = CursorDashboardMenuControl.PanelOuterWidth,
                };
                var dash = new CursorDashboardMenuControl();
                dash.Update(dashBundle, _exchangeRate);
                dashHost.Header = dash;
                root.Items.Add(dashHost);
            }
            else root.Click += (_, _) => OpenProvider(snapshot.Provider);
            menu.Items.Add(root);
        }

        if (menu.Items.Count == 0)
        {
            var installed = ProviderAvailability.InstalledProviders();
            if (installed.Count == 0)
                menu.Items.Add(new MenuItem { Header = Localizer.Get("noProviders"), IsEnabled = false });
            else
                foreach (var provider in installed)
                    menu.Items.Add(new MenuItem { Header = $"{ProviderNames.DisplayName(provider)} — {Localizer.Get("loading")}", IsEnabled = false });
        }

        menu.Items.Add(new Separator());
        var refresh = new MenuItem { Header = Localizer.Get("refresh") };
        refresh.Click += async (_, _) => await RefreshUsageAsync(force: true);
        menu.Items.Add(refresh);
        menu.Items.Add(BuildCurrencyMenu());
        menu.Items.Add(BuildVoiceAlertsMenu());

        var login = new MenuItem { Header = Localizer.Get("openAtLogin"), IsCheckable = true, IsChecked = Settings.IsOpenAtLoginEnabled() };
        login.Click += (_, _) =>
        {
            try { Settings.SetOpenAtLogin(login.IsChecked); }
            catch (Exception error) { MessageBox.Show(error.Message, "AI Usage", MessageBoxButton.OK, MessageBoxImage.Warning); }
        };
        menu.Items.Add(login);
        menu.Items.Add(new Separator());

        var about = new MenuItem { Header = Localizer.Get("about") };
        about.Click += (_, _) => ShowAbout();
        menu.Items.Add(about);
        var feedback = new MenuItem { Header = Localizer.Get("feedback") };
        feedback.Click += (_, _) => OpenFeedbackForm();
        menu.Items.Add(feedback);
        var updates = new MenuItem { Header = Localizer.Get("updates") };
        updates.Click += (_, _) => OpenUrl(GetUpdatesUrl());
        menu.Items.Add(updates);
        menu.Items.Add(new Separator());

        var restart = new MenuItem { Header = Localizer.Get("restart") };
        restart.Click += (_, _) => Restart();
        menu.Items.Add(restart);
        var quit = new MenuItem { Header = Localizer.Get("quit") };
        quit.Click += (_, _) => Close();
        menu.Items.Add(quit);
        menu.Closed += (_, _) => _speech.StopPreview();
        return menu;
    }

    private MenuItem BuildCurrencyMenu()
    {
        var root = new MenuItem { Header = Localizer.Get("currency") };
        var currencies = new[] { ("usd", "usd"), ("eur", "eur"), ("jpy", "jpy"), ("gbp", "gbp"), ("cny", "cny") };
        foreach (var (code, key) in currencies)
        {
            var item = new MenuItem { Header = Localizer.Get(key), IsCheckable = true, IsChecked = Settings.Currency == code, Tag = code };
            item.Click += async (_, _) =>
            {
                Settings.SetCurrency(code);
                foreach (MenuItem currencyItem in root.Items)
                    currencyItem.IsChecked = Equals(currencyItem.Tag, code);
                _ = await CurrencyService.GetRateAsync(code);
                await RefreshUsageAsync(force: true);
            };
            root.Items.Add(item);
        }
        return root;
    }

    private MenuItem BuildVoiceAlertsMenu()
    {
        var root = new MenuItem { Header = Localizer.Get("voiceAlerts") };
        var enabled = new MenuItem { Header = Localizer.Get("voiceEnabled"), IsCheckable = true, IsChecked = Settings.VoiceAlertsEnabled };
        enabled.Click += (_, _) => Settings.VoiceAlertsEnabled = enabled.IsChecked;
        root.Items.Add(enabled);
        root.Items.Add(new Separator());
        foreach (var threshold in Settings.VoiceThresholds)
        {
            var item = new MenuItem
            {
                Header = Localizer.Get("threshold", threshold),
                IsCheckable = true,
                IsChecked = Settings.IsThresholdEnabled(threshold),
                Tag = threshold,
            };
            item.MouseEnter += (_, _) => _speech.Preview(_displayProvider, "standard", threshold);
            item.MouseLeave += (_, _) => _speech.StopPreview();
            item.Click += (_, _) => Settings.SetThresholdEnabled(threshold, item.IsChecked);
            root.Items.Add(item);
        }
        root.SubmenuClosed += (_, _) => _speech.StopPreview();
        return root;
    }

    private static string GetUpdatesUrl()
    {
        var storeId = Environment.GetEnvironmentVariable("MS_STORE_PRODUCT_ID");
        return string.IsNullOrWhiteSpace(storeId)
            ? "https://github.com/tomippe/ai-usage/releases"
            : $"https://apps.microsoft.com/detail/{storeId.Trim()}";
    }

    private void OpenProvider(ProviderKind provider)
    {
        _displayProvider = provider;
        Settings.LastProvider = provider;
        UpdateDisplay();
        try
        {
            switch (provider)
            {
                case ProviderKind.Cursor:
                    StartPathOrCommand(ProviderAvailability.FindCursorApp(), "cursor");
                    break;
                case ProviderKind.Codex:
                    var appId = ProviderAvailability.FindChatGPTAppId();
                    if (appId is not null)
                        Process.Start(new ProcessStartInfo("explorer.exe", $"shell:AppsFolder\\{appId}") { UseShellExecute = true });
                    else StartPathOrCommand(ProviderAvailability.FindCodexCommand(), "codex");
                    break;
                case ProviderKind.Claude:
                    StartPathOrCommand(ProviderAvailability.FindExecutable("claude"), "claude");
                    break;
            }
        }
        catch { }
    }

    private static void StartPathOrCommand(string? path, string command)
    {
        if (path is not null)
        {
            if (path.EndsWith(".cmd", StringComparison.OrdinalIgnoreCase) || path.EndsWith(".bat", StringComparison.OrdinalIgnoreCase))
                Process.Start(new ProcessStartInfo("cmd.exe", $"/k \"\"{path}\"\"") { UseShellExecute = true });
            else Process.Start(new ProcessStartInfo(path) { UseShellExecute = true });
        }
        else Process.Start(new ProcessStartInfo("cmd.exe", $"/k {command}") { UseShellExecute = true });
    }

    private static void ShowAbout()
    {
        var version = Assembly.GetExecutingAssembly().GetName().Version?.ToString(3) ?? "1.0.0";
        MessageBox.Show(Localizer.Get("aboutBody", version) + "\n\nhttps://apps.tomippe.jp/ai-usage/",
            Localizer.Get("about"), MessageBoxButton.OK, MessageBoxImage.Information);
    }

    private static void OpenFeedbackForm()
    {
        var forms = Localizer.LanguageIndex switch
        {
            1 => "https://airtable.com/appIpAuwoVRCxzjcr/shrJql8sZUaekKD6Y",
            2 => "https://airtable.com/appIpAuwoVRCxzjcr/shrYSDAi2CVNPkCCs",
            _ => "https://airtable.com/appIpAuwoVRCxzjcr/shrWhPOixBEspTNwS",
        };
        var version = Assembly.GetExecutingAssembly().GetName().Version?.ToString(3) ?? "1.0.0";
        var os = Environment.OSVersion.Version;
        var osName = $"Windows {os.Major}.{os.Minor}";
        var query = $"prefill_App=AI%20Usage&prefill_Version={Uri.EscapeDataString(version)}&prefill_OS={Uri.EscapeDataString(osName)}";
        OpenUrl(forms + "?" + query);
    }

    private static void OpenUrl(string url) => Process.Start(new ProcessStartInfo(url) { UseShellExecute = true });

    private void Restart()
    {
        var executable = ResolveExecutablePath();
        if (string.IsNullOrWhiteSpace(executable)) return;

        var dir = Path.GetDirectoryName(executable);
        try
        {
            Process.Start(new ProcessStartInfo(executable)
            {
                UseShellExecute = true,
                WorkingDirectory = string.IsNullOrEmpty(dir) ? Environment.CurrentDirectory : dir,
            });
        }
        catch (Exception ex)
        {
            MessageBox.Show(ex.Message, "AI Usage", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }

        // Close() だけだと再帰コンテキストメニューやリリースビルドでプロセスが残ることがある
        Application.Current.Shutdown();
    }

    /// <summary>単一ファイル publish や稀な環境で <see cref="Environment.ProcessPath"/> が空でも起動パスを得る。</summary>
    private static string? ResolveExecutablePath()
    {
        var path = Environment.ProcessPath;
        if (!string.IsNullOrWhiteSpace(path) && File.Exists(path))
            return path;

        try
        {
            path = Process.GetCurrentProcess().MainModule?.FileName;
            if (!string.IsNullOrWhiteSpace(path) && File.Exists(path))
                return path;
        }
        catch { /* アクセス拒否等 */ }

        var asm = Assembly.GetExecutingAssembly().Location;
        if (!string.IsNullOrWhiteSpace(asm) && File.Exists(asm))
            return asm;

        return null;
    }

    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
}
