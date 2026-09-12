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
        Assert.Equal(5, SoundPacks.Catalog.Count);
        Assert.True(sounds.Count >= 35);
        Assert.Equal(sounds.Count, sounds.Select(s => s.ClipId).Distinct().Count());
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
}
