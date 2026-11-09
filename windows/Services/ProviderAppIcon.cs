using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using AIUsage.Windows.Models;

namespace AIUsage.Windows.Services;

/// <summary>インストール済みアプリの実行ファイル／シェルパスからアイコンを読む（リポジトリにコピーしない）。</summary>
internal static class ProviderAppIcon
{
    private const int MenuBarIconSize = 16;
    private static readonly Dictionary<string, ImageSource?> Cache = new(StringComparer.OrdinalIgnoreCase);

    public static ImageSource? GetIcon(ProviderKind provider)
    {
        foreach (var path in IconPaths(provider))
        {
            var icon = LoadIcon(path);
            if (icon is not null) return icon;
        }
        return null;
    }

    public static void ClearCache()
    {
        lock (Cache) Cache.Clear();
    }

    private static IEnumerable<string> IconPaths(ProviderKind provider)
    {
        switch (provider)
        {
            case ProviderKind.Cursor:
                if (ProviderAvailability.FindCursorApp() is { } cursor) yield return cursor;
                break;
            case ProviderKind.Codex:
                foreach (var brand in ProviderAvailability.FindChatGPTBrandIconPaths()) yield return brand;
                if (ProviderAvailability.FindChatGPTAppId() is { } appId)
                    yield return $"shell:AppsFolder\\{appId}";
                if (ProviderAvailability.FindChatGPTApp() is { } chatGpt) yield return chatGpt;
                break;
            case ProviderKind.Claude:
                if (ProviderAvailability.FindExecutable("claude") is { } claude) yield return claude;
                break;
        }
    }

    private static ImageSource? LoadIcon(string path)
    {
        lock (Cache)
        {
            if (Cache.TryGetValue(path, out var cached)) return cached;
        }

        var loaded = TryLoadIcon(path);
        lock (Cache) Cache[path] = loaded;
        return loaded;
    }

    private static ImageSource? TryLoadIcon(string path)
    {
        if (path.EndsWith(".png", StringComparison.OrdinalIgnoreCase) && File.Exists(path))
            return LoadPng(path);
        if (path.EndsWith(".ico", StringComparison.OrdinalIgnoreCase) && File.Exists(path))
            return LoadIco(path);

        // 実ファイルでは .exe の埋め込みアイコンを直接取る（SHGFI_SMALL は汎用アイコンになることがある）
        if (!path.StartsWith("shell:", StringComparison.OrdinalIgnoreCase)
            && path.EndsWith(".exe", StringComparison.OrdinalIgnoreCase)
            && File.Exists(path))
        {
            try
            {
                using var sysIcon = Icon.ExtractAssociatedIcon(path);
                if (sysIcon is not null)
                {
                    var source = Imaging.CreateBitmapSourceFromHIcon(
                        sysIcon.Handle,
                        Int32Rect.Empty,
                        BitmapSizeOptions.FromWidthAndHeight(MenuBarIconSize, MenuBarIconSize));
                    source.Freeze();
                    return source;
                }
            }
            catch { /* fall through */ }
        }

        try
        {
            var info = new SHFILEINFO();
            var isShell = path.StartsWith("shell:", StringComparison.OrdinalIgnoreCase);
            // デフォルト（大）アイコンを取得してから縮小（SHGFI_SMALLICON は汎用・白紙になることがある）
            var flags = SHGFI_ICON;
            if (isShell) flags |= SHGFI_USEFILEATTRIBUTES;
            var attributes = isShell ? FILE_ATTRIBUTE_NORMAL : 0u;
            var result = SHGetFileInfo(path, attributes, ref info, (uint)Marshal.SizeOf<SHFILEINFO>(), flags);
            if (result == IntPtr.Zero || info.hIcon == IntPtr.Zero) return null;

            try
            {
                var source = Imaging.CreateBitmapSourceFromHIcon(
                    info.hIcon,
                    Int32Rect.Empty,
                    BitmapSizeOptions.FromWidthAndHeight(MenuBarIconSize, MenuBarIconSize));
                source.Freeze();
                return source;
            }
            finally
            {
                DestroyIcon(info.hIcon);
            }
        }
        catch
        {
            return null;
        }
    }

    private static ImageSource? LoadPng(string path)
    {
        try
        {
            var image = new BitmapImage();
            image.BeginInit();
            image.UriSource = new Uri(path, UriKind.Absolute);
            image.DecodePixelWidth = MenuBarIconSize * 2;
            image.CacheOption = BitmapCacheOption.OnLoad;
            image.EndInit();
            image.Freeze();
            return image;
        }
        catch
        {
            return null;
        }
    }

    private static ImageSource? LoadIco(string path)
    {
        try
        {
            using var icon = new Icon(path, MenuBarIconSize, MenuBarIconSize);
            var source = Imaging.CreateBitmapSourceFromHIcon(
                icon.Handle,
                Int32Rect.Empty,
                BitmapSizeOptions.FromWidthAndHeight(MenuBarIconSize, MenuBarIconSize));
            source.Freeze();
            return source;
        }
        catch
        {
            try
            {
                using var icon = new Icon(path);
                using var sized = new Icon(icon, new System.Drawing.Size(MenuBarIconSize, MenuBarIconSize));
                var source = Imaging.CreateBitmapSourceFromHIcon(
                    sized.Handle,
                    Int32Rect.Empty,
                    BitmapSizeOptions.FromWidthAndHeight(MenuBarIconSize, MenuBarIconSize));
                source.Freeze();
                return source;
            }
            catch
            {
                return null;
            }
        }
    }

    private const uint SHGFI_ICON = 0x000000100;
    private const uint SHGFI_USEFILEATTRIBUTES = 0x000000010;
    private const uint FILE_ATTRIBUTE_NORMAL = 0x00000080;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct SHFILEINFO
    {
        public IntPtr hIcon;
        public int iIcon;
        public uint dwAttributes;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)]
        public string szDisplayName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 80)]
        public string szTypeName;
    }

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr SHGetFileInfo(string pszPath, uint dwFileAttributes, ref SHFILEINFO psfi, uint cbFileInfo, uint uFlags);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool DestroyIcon(IntPtr hIcon);
}
