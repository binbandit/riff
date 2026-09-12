using System.Security.Cryptography;
using System.Text;

namespace Riff.Companion;

public sealed class AISettings
{
    readonly string path;
    string? apiKey;
    public string? ApiKey => Volatile.Read(ref apiKey);
    public bool Enabled => !string.IsNullOrEmpty(ApiKey);

    public AISettings(string folder)
    {
        path = Path.Combine(folder, "openai-key.bin");
        try
        {
            if (File.Exists(path)) apiKey = Encoding.UTF8.GetString(ProtectedData.Unprotect(File.ReadAllBytes(path), null, DataProtectionScope.CurrentUser));
        }
        catch (Exception ex) when (ex is IOException or CryptographicException or UnauthorizedAccessException)
        { apiKey = null; }
    }

    public void Save(string value)
    {
        var key = value.Trim();
        if (key.Length is < 10 or > 1024 || key.Any(char.IsWhiteSpace) || key.Any(char.IsControl))
            throw new ArgumentException("Paste a valid OpenAI API key.");
        var encrypted = ProtectedData.Protect(Encoding.UTF8.GetBytes(key), null, DataProtectionScope.CurrentUser);
        var temporary = path + ".tmp";
        File.WriteAllBytes(temporary, encrypted);
        File.Move(temporary, path, true);
        Volatile.Write(ref apiKey, key);
    }

    public void Disable()
    {
        File.Delete(path);
        Volatile.Write(ref apiKey, null);
    }
}
