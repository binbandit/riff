using Riff.Companion;
using Xunit;

namespace Riff.WindowsTests;

public class LegacyAIKeyCleanupTests
{
    [Fact]
    public void StartupDeletesLegacyCredentialsWithoutReadingThem()
    {
        var folder = Path.Combine(Path.GetTempPath(), "riff-ai-cleanup-" + Guid.NewGuid());
        Directory.CreateDirectory(folder);
        try
        {
            var keyPath = Path.Combine(folder, "openai-key.bin");
            File.WriteAllBytes(keyPath, [0xff, 0, 0x80]);
            File.WriteAllBytes(keyPath + ".tmp", [1, 2, 3]);
            var store = new StateStore(folder);
            Assert.False(File.Exists(keyPath));
            Assert.False(File.Exists(keyPath + ".tmp"));
            Assert.Equal(store.State.Version, new StateStore(folder).State.Version);
        }
        finally { Directory.Delete(folder, true); }
    }
}
