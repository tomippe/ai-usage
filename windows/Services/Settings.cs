using System.Text.Json;
using AIUsage.Windows.Models;
using Microsoft.Win32;

namespace AIUsage.Windows.Services;

internal static class Settings
{
    private static readonly object Gate = new();
    private static readonly string Folder = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "AI Usage");
    private static readonly string FilePath = Path.Combine(Folder, "settings.json");
    private static SettingsData _data = new();

    private sealed class SettingsData
    {
        public string LastProvider { get; set; } = nameof(ProviderKind.Cursor);
        public string Currency { get; set; } = "";
        public bool VoiceAlertsEnabled { get; set; }
        public Dictionary<int, bool> VoiceThresholds { get; set; } = [];
        public double? WindowLeft { get; set; }
        public double? WindowTop { get; set; }
        public Dictionary<string, RateCacheEntry> Rates { get; set; } = [];
    }

    public sealed class RateCacheEntry
    {
        public double Rate { get; set; }
        public DateTimeOffset FetchedAt { get; set; }
    }

    public static readonly int[] VoiceThresholds = [50, 40, 30, 20, 10, 5, 0];

    public static void Load()
    {
        lock (Gate)
        {
            try
            {
                if (File.Exists(FilePath))
                    _data = JsonSerializer.Deserialize<SettingsData>(File.ReadAllText(FilePath)) ?? new SettingsData();
            }
            catch
            {
                _data = new SettingsData();
            }
        }
    }

    public static string Currency
    {
        get
        {
            lock (Gate)
            {
                if (!string.IsNullOrWhiteSpace(_data.Currency)) return _data.Currency;
                return Localizer.LanguageIndex switch { 1 => "jpy", 2 => "cny", _ => "usd" };
            }
        }
    }

    public static void SetCurrency(string currency)
    {
        lock (Gate) { _data.Currency = currency; SaveLocked(); }
    }

    public static ProviderKind LastProvider
    {
        get => Enum.TryParse<ProviderKind>(_data.LastProvider, true, out var value) ? value : ProviderKind.Cursor;
        set { lock (Gate) { _data.LastProvider = value.ToString(); SaveLocked(); } }
    }

    public static bool VoiceAlertsEnabled
    {
        get { lock (Gate) return _data.VoiceAlertsEnabled; }
        set { lock (Gate) { _data.VoiceAlertsEnabled = value; SaveLocked(); } }
    }

    public static bool IsThresholdEnabled(int threshold)
    {
        lock (Gate) return !_data.VoiceThresholds.TryGetValue(threshold, out var enabled) || enabled;
    }

    public static void SetThresholdEnabled(int threshold, bool enabled)
    {
        lock (Gate) { _data.VoiceThresholds[threshold] = enabled; SaveLocked(); }
    }

    public static (double? Left, double? Top) WindowPosition
    {
        get { lock (Gate) return (_data.WindowLeft, _data.WindowTop); }
    }

    public static void SetWindowPosition(double left, double top)
    {
        lock (Gate) { _data.WindowLeft = left; _data.WindowTop = top; SaveLocked(); }
    }

    public static RateCacheEntry? GetRate(string code)
    {
        lock (Gate) return _data.Rates.TryGetValue(code, out var entry) ? entry : null;
    }

    public static void SetRate(string code, double rate)
    {
        lock (Gate)
        {
            _data.Rates[code] = new RateCacheEntry { Rate = rate, FetchedAt = DateTimeOffset.UtcNow };
            SaveLocked();
        }
    }

    public static bool IsOpenAtLoginEnabled()
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run");
            return key?.GetValue("AI Usage") is string;
        }
        catch { return false; }
    }

    public static void SetOpenAtLogin(bool enabled)
    {
        using var key = Registry.CurrentUser.CreateSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run");
        if (enabled)
        {
            var exe = Environment.ProcessPath ?? throw new InvalidOperationException("Application path is unavailable.");
            key.SetValue("AI Usage", $"\"{exe}\"");
        }
        else
        {
            key.DeleteValue("AI Usage", false);
        }
    }

    private static void SaveLocked()
    {
        try
        {
            Directory.CreateDirectory(Folder);
            var temporary = FilePath + ".tmp";
            File.WriteAllText(temporary, JsonSerializer.Serialize(_data, new JsonSerializerOptions { WriteIndented = true }));
            File.Move(temporary, FilePath, true);
        }
        catch { /* Keep the in-memory preference if the profile cannot be written. */ }
    }
}
