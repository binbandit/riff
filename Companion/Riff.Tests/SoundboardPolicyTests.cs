using System.Text.Json;
using Riff.Core;
using Xunit;

namespace Riff.Tests;

public class SoundboardPolicyTests
{
    [Theory]
    [InlineData("hotkey")]
    [InlineData("text")]
    [InlineData("media")]
    [InlineData("url")]
    [InlineData("app")]
    [InlineData("macro")]
    [InlineData("unknown")]
    public void SoundboardModeRejectsEveryNonSoundAction(string kind)
    {
        var error = Assert.Throws<ArgumentException>(() => SoundboardPolicy.EnsureAllowed(kind, true));
        Assert.Equal(SoundboardPolicy.BlockedMessage, error.Message);
    }

    [Fact]
    public void SoundPlaybackRemainsAvailableAndDesktopActionsRequireOptIn()
    {
        SoundboardPolicy.EnsureAllowed("sound", true);
        foreach (var kind in Rules.Kinds) SoundboardPolicy.EnsureAllowed(kind, false);
    }

    [Fact]
    public void ExistingSavedStateDefaultsToSoundboardModeAndExplicitChoiceSurvivesReload()
    {
        const string legacy = """{"version":1,"decks":[],"clips":[],"outputId":"","volume":0.75,"apps":[]}""";
        var state = JsonSerializer.Deserialize<SavedState>(legacy, Wire.Json)!;
        Assert.True(state.SoundboardOnly);
        var optedIn = state with { SoundboardOnly = false };
        Assert.False(JsonSerializer.Deserialize<SavedState>(JsonSerializer.Serialize(optedIn, Wire.Json), Wire.Json)!.SoundboardOnly);
    }
}
