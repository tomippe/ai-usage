using System.Security.Cryptography;
using System.Text;
using AIUsage.Windows.Services;
using Xunit;

namespace AIUsage.Windows.Tests;

public class CursorSafeStorageTests
{
    private static string UnsignedJwt(string sub)
    {
        var payload = Convert.ToBase64String(Encoding.UTF8.GetBytes($$"""{"sub":"{{sub}}"}"""))
            .TrimEnd('=').Replace('+', '-').Replace('/', '_');
        return $"eyJhbGciOiJub25lIn0.{payload}.sig";
    }

    [Fact]
    public void PlainJwt_passes_through_unchanged()
    {
        var jwt = UnsignedJwt("google-oauth2|12345");
        Assert.Equal(jwt, CursorSafeStorage.ResolveAccessToken(jwt));
    }

    [Fact]
    public void Windows_v10_gcm_roundtrip()
    {
        var jwt = UnsignedJwt("auth0|user_01");
        var key = RandomNumberGenerator.GetBytes(32);
        var iv = new byte[12];
        RandomNumberGenerator.Fill(iv);

        var plain = Encoding.UTF8.GetBytes(jwt);
        var cipher = new byte[plain.Length];
        var tag = new byte[16];
        using (var gcm = new AesGcm(key, 16))
            gcm.Encrypt(iv, plain, cipher, tag);

        var blob = new byte[3 + iv.Length + cipher.Length + tag.Length];
        Encoding.UTF8.GetBytes("v10").CopyTo(blob, 0);
        iv.CopyTo(blob, 3);
        cipher.CopyTo(blob, 3 + iv.Length);
        tag.CopyTo(blob, 3 + iv.Length + cipher.Length);

        var stored = CursorSafeStorage.Prefix + Convert.ToBase64String(blob);
        var ciphertext = Convert.FromBase64String(stored[CursorSafeStorage.Prefix.Length..]);

        var decrypted = CursorSafeStorage.DecryptWindowsOsCryptGcm(ciphertext, key);
        Assert.Equal(jwt, decrypted);
    }
}
