using System.Text.Json;
using NAudio.Wave;
using Riff.Companion;
using Riff.Core;
using Xunit;

namespace Riff.Tests;

public class SoundLoopTests
{
    [Fact] public void LoopRefillsBuffersAcrossMultipleBoundaries()
    {
        using var source = new RawSourceWaveStream(new MemoryStream([1, 2, 3, 4]), new WaveFormat(8000, 8, 1));
        using var loop = new LoopingWaveStream(source);
        byte[] buffer = new byte[12];
        Assert.Equal(10, loop.Read(buffer, 1, 10));
        Assert.Equal(new byte[] { 0, 1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 0 }, buffer);
        Assert.Equal(4, loop.Read(buffer, 0, 4));
        Assert.Equal(new byte[] { 3, 4, 1, 2 }, buffer[..4]);
    }

    [Fact] public void EmptySoundDoesNotSpinForever()
    {
        using var source = new RawSourceWaveStream(new MemoryStream(), new WaveFormat(8000, 8, 1));
        using var loop = new LoopingWaveStream(source);
        Assert.Equal(0, loop.Read(new byte[8], 0, 8));
    }

    [Fact] public void LoopPersistsAndDoesNotLeakIntoSecondaryGestures()
    {
        var pad = new Pad("music", "Music", "music.note", "orange", "sound", "clip", [],
            HoldAction: new("sound", "effect"), Loop: true);
        var restored = JsonSerializer.Deserialize<Pad>(JsonSerializer.Serialize(pad, Wire.Json), Wire.Json)!;
        Assert.True(restored.Resolve("tap").Loop);
        Assert.False(restored.Resolve("hold").Loop);
        var legacy = JsonSerializer.Deserialize<Pad>("""{"id":"old","title":"Sound","icon":"music.note","color":"orange","kind":"sound","value":"clip","steps":[]}""", Wire.Json)!;
        Assert.False(legacy.Loop);
    }
}
