using System.Globalization;
using System.Resources;

namespace AIUsage.Windows.Services;

internal static class Localizer
{
    private static readonly ResourceManager Rm =
        new("AIUsage.Windows.Resources.Strings", typeof(Localizer).Assembly);

    public static int LanguageIndex
    {
        get
        {
            var language = CultureInfo.CurrentUICulture.Name;
            if (language.StartsWith("ja", StringComparison.OrdinalIgnoreCase)) return 1;
            if (language.StartsWith("zh", StringComparison.OrdinalIgnoreCase)) return 2;
            return 0;
        }
    }

    public static string Get(string key, params object[] args)
    {
        var value = Rm.GetString(key, CultureInfo.CurrentUICulture) ?? key;
        return args.Length == 0 ? value : string.Format(CultureInfo.CurrentCulture, value, args);
    }
}
