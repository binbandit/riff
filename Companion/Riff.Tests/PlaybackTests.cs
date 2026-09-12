using System.Text.Json;
using Riff.Core;
using Xunit;

namespace Riff.Tests;

public class PlaybackTests
{
    [Theory]
    [InlineData("overlap")]
    [InlineData("single")]
    [InlineData("queue")]
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
    [Fact] public void QueueStartsImmediatelyWhenIdleAndWaitsForAllActiveSounds()
    {
        Assert.True(PlaybackPolicy.Plan([], "first", true, "queue").Start);
        var plan = PlaybackPolicy.Plan([new("a", "first"), new("b", "other")], "next", true, "queue");
        Assert.False(plan.Start);
        Assert.True(plan.Enqueue);
        Assert.Empty(plan.StopIds);
        // A sound arriving between completion and queue advancement must stay behind those waiting.
        Assert.True(PlaybackPolicy.Plan([], "new", true, "queue", [new("q", "waiting")]).Enqueue);
    }
    [Fact] public void TappingWaitingSoundRemovesItWithoutInterruptingPlayback()
    {
        var plan = PlaybackPolicy.Plan([new("a", "first")], "waiting", true, "queue", [new("q1", "waiting"), new("q2", "last")]);
        Assert.False(plan.Start);
        Assert.False(plan.Enqueue);
        Assert.Empty(plan.StopIds);
        Assert.Equal(["q1"], plan.RemoveQueuedIds);
    }
    [Fact] public void FullQueueAllowsCancellationButRejectsMoreSounds()
    {
        var full = Enumerable.Range(0, 48).Select(i => new ActiveSound("q" + i, "pad" + i)).ToList();
        Assert.Throws<ArgumentException>(() => PlaybackPolicy.Plan([new("a", "playing")], "new", true, "queue", full));
        Assert.Equal(["q0"], PlaybackPolicy.Plan([new("a", "playing")], "pad0", true, "queue", full).RemoveQueuedIds);
        Assert.Equal(["a"], PlaybackPolicy.Plan([new("a", "playing")], "playing", true, "queue", full).StopIds);
    }
    [Theory]
    [InlineData("overlap")]
    [InlineData("single")]
    public void SwitchingModesClearsWaitingSounds(string mode)
    {
        var plan = PlaybackPolicy.Plan([new("a", "first")], "next", true, mode, [new("q1", "waiting"), new("q2", "last")]);
        Assert.True(plan.Start);
        Assert.Equal(["q1", "q2"], plan.RemoveQueuedIds);
    }
    [Fact] public void QueueStatePreservesOrderAndOlderStatesStillDecode()
    {
        var state = new PlaybackState("pc", 4, ["first"], ["third", "second"]);
        var restored = JsonSerializer.Deserialize<PlaybackState>(JsonSerializer.Serialize(state, Wire.Json), Wire.Json)!;
        Assert.Equal(["third", "second"], restored.QueuedPadIds);
        Assert.Null(JsonSerializer.Deserialize<PlaybackState>("""{"sessionId":"pc","revision":0,"padIds":[]}""", Wire.Json)!.QueuedPadIds);
    }
}
