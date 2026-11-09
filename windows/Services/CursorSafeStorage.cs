using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace AIUsage.Windows.Services;

/// <summary>Cursor <c>cursor-safe-storage:v1:</c> 形式のアクセストークンを JWT に戻す（Windows / Chromium OSCrypt GCM）。</summary>
internal static class CursorSafeStorage
{
    public const string Prefix = "cursor-safe-storage:v1:";

    private static readonly byte[] DpapiPrefix = "DPAPI"u8.ToArray();
    private const int GcmNonceLength = 12;
    private const int GcmTagLength = 16;

    private static byte[]? _cachedOsCryptKey;

    /// <summary>平文 JWT はそのまま。暗号化値は復号して JWT を返す。失敗時は null（トークン内容は漏らさない）。</summary>
    public static string? ResolveAccessToken(string stored)
    {
        if (string.IsNullOrWhiteSpace(stored)) return null;
        if (!stored.StartsWith(Prefix, StringComparison.Ordinal)) return stored;

        try
        {
            var ciphertext = Convert.FromBase64String(stored[Prefix.Length..]);
            if (ciphertext.Length < 3) return null;

            var envelope = Encoding.UTF8.GetString(ciphertext, 0, 3);
            if (envelope is "v10" or "v11")
                return DecryptWindowsOsCryptGcm(ciphertext, GetWindowsOsCryptKey());

            var plain = UnprotectDpapi(ciphertext);
            return Encoding.UTF8.GetString(plain);
        }
        catch
        {
            return null;
        }
    }

    internal static string DecryptWindowsOsCryptGcm(byte[] ciphertext, byte[] aesKey)
    {
        if (aesKey.Length != 32)
            throw new CryptographicException("OSCrypt key has unexpected length");

        var envelope = Encoding.UTF8.GetString(ciphertext, 0, 3);
        if (envelope is not ("v10" or "v11"))
            throw new CryptographicException("Unsupported Windows safeStorage envelope");

        var minimum = 3 + GcmNonceLength + GcmTagLength + 1;
        if (ciphertext.Length < minimum)
            throw new CryptographicException("Cursor access token ciphertext is too short");

        var nonce = ciphertext.AsSpan(3, GcmNonceLength);
        var tag = ciphertext.AsSpan(ciphertext.Length - GcmTagLength, GcmTagLength);
        var data = ciphertext.AsSpan(3 + GcmNonceLength, ciphertext.Length - 3 - GcmNonceLength - GcmTagLength);
        var plain = new byte[data.Length];
        using var gcm = new AesGcm(aesKey, GcmTagLength);
        gcm.Decrypt(nonce, data, tag, plain);
        return Encoding.UTF8.GetString(plain);
    }

    private static byte[] GetWindowsOsCryptKey()
    {
        if (_cachedOsCryptKey is not null) return _cachedOsCryptKey;

        var localStatePath = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            "Cursor",
            "Local State");
        if (!File.Exists(localStatePath))
            throw new InvalidOperationException("Cursor Local State is missing");

        using var doc = JsonDocument.Parse(File.ReadAllText(localStatePath));
        if (!doc.RootElement.TryGetProperty("os_crypt", out var osCrypt)
            || !osCrypt.TryGetProperty("encrypted_key", out var keyElement)
            || keyElement.ValueKind != JsonValueKind.String)
            throw new InvalidOperationException("Cursor Local State is missing os_crypt.encrypted_key");

        var wrapped = Convert.FromBase64String(keyElement.GetString()!);
        if (wrapped.Length <= DpapiPrefix.Length || !wrapped.AsSpan(0, DpapiPrefix.Length).SequenceEqual(DpapiPrefix))
            throw new InvalidOperationException("Cursor Local State key is not DPAPI-wrapped");

        var key = UnprotectDpapi(wrapped.AsSpan(DpapiPrefix.Length).ToArray());
        if (key.Length != 32)
            throw new InvalidOperationException("Cursor OSCrypt key has unexpected length");

        _cachedOsCryptKey = key;
        return key;
    }

    private static byte[] UnprotectDpapi(byte[] ciphertext) =>
        ProtectedData.Unprotect(ciphertext, null, DataProtectionScope.CurrentUser);

    internal static void ClearOsCryptKeyCacheForTests() => _cachedOsCryptKey = null;
}
