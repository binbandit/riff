using System.Text;
using Riff.Companion;
using Xunit;

namespace Riff.WindowsTests;

public class AISettingsTests
{
    [Fact]
    public void KeyIsEncryptedRestoredAndRemoved()
    {
        var folder = Path.Combine(Path.GetTempPath(), "riff-ai-test-" + Guid.NewGuid());
        Directory.CreateDirectory(folder);
        try
        {
            var settings = new AISettings(folder);
            Assert.False(settings.Enabled);
            const string key = "sk-test-only-not-a-real-key";
            settings.Save(key);
            Assert.True(settings.Enabled);
            Assert.Equal(key, new AISettings(folder).ApiKey);
            var path = Path.Combine(folder, "openai-key.bin");
            Assert.DoesNotContain(key, Encoding.UTF8.GetString(File.ReadAllBytes(path)));
            settings.Disable();
            Assert.False(settings.Enabled);
            Assert.False(File.Exists(path));
            Assert.False(new AISettings(folder).Enabled);
            Assert.Throws<ArgumentException>(() => settings.Save(" "));
            File.WriteAllText(path, "corrupt key file");
            Assert.False(new AISettings(folder).Enabled);
        }
        finally { Directory.Delete(folder, true); }
    }
}
