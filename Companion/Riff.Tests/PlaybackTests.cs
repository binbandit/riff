using System.Text.Json;
using Riff.Core;
using Xunit;

namespace Riff.Tests;

public class PlaybackTests
{
    [Theory]
    [InlineData("overlap")]
    [InlineData("single")]
    public void TappingPlayingButtonStopsOnlyItsInstances(string mode)
    {
        var plan = PlaybackPolicy.Plan([new("a", "pilot"), new("b", "meme"), new("c", "pilot")], "pilot", true, mode);
        Assert.False(plan.Start);
        Assert.Equal(["a", "c"], plan.StopIds);
    }
    [Fact] public void SingleModeReplacesEverySoundIncludingPreviews()
    {
        var plan = PlaybackPolicy.Plan([new("a", "pilot"), new("b", "")], "meme", true, "single");
        Assert.True(plan.Start);
        Assert.Equal(["a", "b"], plan.StopIds);
    }
    [Fact] public void OverlapLeavesOtherButtonsPlaying()
    {
        var plan = PlaybackPolicy.Plan([new("a", "pilot")], "meme", true, "overlap");
        Assert.True(plan.Start);
        Assert.Empty(plan.StopIds);
    }
    [Fact] public void FullMixerStillAllowsStoppingOrReplacing()
    {
        var full = Enumerable.Range(0, 16).Select(i => new ActiveSound(i.ToString(), "pad" + i)).ToList();
        Assert.Throws<ArgumentException>(() => PlaybackPolicy.Plan(full, "new", true, "overlap"));
        Assert.False(PlaybackPolicy.Plan(full, "pad0", true, "overlap").Start);
        Assert.Equal(16, PlaybackPolicy.Plan(full, "new", true, "single").StopIds.Count);
    }
    [Fact] public void LegacyRequestsKeepRetriggeringAndPreviewsDoNotToggleEachOther()
    {
        var legacy = JsonSerializer.Deserialize<Trigger>("""{"padId":"pilot","requestId":"123"}""", Wire.Json)!;
        Assert.False(legacy.Toggle);
        Assert.Null(legacy.SoundMode);
        Assert.True(PlaybackPolicy.Plan([new("a", "pilot")], "pilot", legacy.Toggle, "overlap").Start);
        Assert.True(PlaybackPolicy.Plan([new("a", "")], "", true, "overlap").Start);
        Assert.Throws<ArgumentException>(() => PlaybackPolicy.Plan([], "pilot", true, "invalid"));
    }
}
