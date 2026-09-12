using System.Security.Cryptography;
using Riff.Core;
using Xunit;

namespace Riff.Tests;

public class SoundPackTests
{
    [Fact]
    public void CatalogIsSharedMetadataAndNeverAddsDefaultButtons()
    {
        var sounds = SoundPacks.Catalog.SelectMany(p => p.Sounds).ToList();
        Assert.True(SoundPacks.Catalog.Count >= 14);
        Assert.True(sounds.Count >= 137);
        Assert.Equal(sounds.Count, sounds.Select(s => s.ClipId).Distinct().Count());
        Assert.Equal(sounds.Count, sounds.Select(s => s.Sha256).Distinct().Count());
        Assert.DoesNotContain(Defaults.Decks.SelectMany(d => d.Pads), p => sounds.Any(s => s.ClipId == p.Value));
        Assert.All(sounds, s =>
        {
            Assert.Equal($"{s.Id}-{s.Sha256}.mp3", s.FileName);
            Assert.InRange(s.ByteCount, 1, 20 * 1024 * 1024);
            Assert.InRange(s.Duration, 0.01, 60);
            Assert.Equal(64, s.Sha256.Length);
        });
    }
    [Fact]
    public void OnlyKnownPackAndSoundPairsAreAccepted()
    {
        Assert.Equal("pack-sad-violin", SoundPacks.Find("epic-fails", "sad-violin").ClipId);
        Assert.Throws<ArgumentException>(() => SoundPacks.Find("epic-fails", "smoke-detector"));
        Assert.Throws<ArgumentException>(() => SoundPacks.Find("../clips", "../state.json"));
        Assert.Throws<ArgumentException>(() => SoundPacks.Find("https://example.com", "x"));
    }
    [Fact]
    public void ContentMustMatchBothReviewedSizeAndHash()
    {
        byte[] bytes = [1, 2, 3, 4];
        var sound = SoundPacks.Find("epic-fails", "sad-violin") with { ByteCount = bytes.Length, Sha256 = Convert.ToHexString(SHA256.HashData(bytes)) };
        sound.Validate(bytes);
        Assert.Throws<ArgumentException>(() => sound.Validate([1, 2, 3]));
        Assert.Throws<ArgumentException>(() => sound.Validate([4, 3, 2, 1]));
    }
    [Fact]
    public void PopulatePreservesRenamesDeletionsAndExistingDecks()
    {
        var sound = SoundPacks.Catalog[0].Sounds[0];
        var old = new SavedState(1, Defaults.Decks, [new(sound.ClipId, "My reaction", 2)], "", .75f, []);
        var populated = SoundPacks.Populate(old);
        Assert.Equal(SoundPacks.Catalog.Sum(p => p.Sounds.Count), populated.Clips.Count);
        Assert.Equal("My reaction", populated.Clips.Single(c => c.Id == sound.ClipId).Name);
        Assert.Same(old.Decks, populated.Decks);
        Assert.Same(populated, SoundPacks.Populate(populated));
        var deleted = populated with { Clips = populated.Clips.Where(c => c.Id != sound.ClipId).ToList() };
        Assert.DoesNotContain(SoundPacks.Populate(deleted).Clips, c => c.Id == sound.ClipId);
        var upgraded = SoundPacks.Populate(deleted with { KnownBundledSoundIds = deleted.KnownBundledSoundIds!.Where(id => id != populated.Clips[1].Id).ToList(), Clips = deleted.Clips.Skip(1).ToList() });
        Assert.Contains(upgraded.Clips, c => c.Id == populated.Clips[1].Id);
        Assert.DoesNotContain(upgraded.Clips, c => c.Id == sound.ClipId);
    }

    [Fact]
    public void CorrectedSoundsRefreshDurationsWithoutLosingRenamesOrRestoringDeletions()
    {
        var sound = SoundPacks.Find("lobby-jukebox", "chipi-chapa");
        var populated = SoundPacks.Populate(new SavedState(1, Defaults.Decks, [], "", .75f, []));
        var old = populated with { Clips = populated.Clips.Select(c => c.Id == sound.ClipId ? c with { Name = "My music", Duration = 11.991 } : c).ToList() };
        var updated = SoundPacks.Populate(old);
        var clip = updated.Clips.Single(c => c.Id == sound.ClipId);
        Assert.Equal("My music", clip.Name);
        Assert.Equal(sound.Duration, clip.Duration);
        Assert.InRange(clip.Duration, 9.7, 9.9);
        Assert.Same(old.Decks, updated.Decks);
        Assert.Same(updated, SoundPacks.Populate(updated));
        var deleted = updated with { Clips = updated.Clips.Where(c => c.Id != sound.ClipId).ToList() };
        Assert.DoesNotContain(SoundPacks.Populate(deleted).Clips, c => c.Id == sound.ClipId);
    }

    [Fact]
    public void AudioReplacementOnlyMatchesAnExplicitPreviousRecording()
    {
        byte[] original = [1, 2, 3, 4];
        var sound = SoundPacks.Find("lobby-jukebox", "chipi-chapa") with { PreviousHashes = [Convert.ToHexString(SHA256.HashData(original)).ToLowerInvariant()] };
        Assert.True(sound.Replaces(original));
        Assert.False(sound.Replaces([4, 3, 2, 1]));
        Assert.False((sound with { PreviousHashes = null }).Replaces(original));
    }

}
