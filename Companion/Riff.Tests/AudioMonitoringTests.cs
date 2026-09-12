using System.Text.Json;
using Riff.Core;
using Xunit;

namespace Riff.Tests;

public class AudioMonitoringTests
{
    [Fact]
    public void HeadphoneSettingsAreAcceptedByTheAudioEndpointContract()
    {
        const string request = """{"outputId":"cable","volume":0.75,"monitorEnabled":true,"monitorOutputId":"headphones","monitorVolume":0.4}""";
        var settings = JsonSerializer.Deserialize<AudioSettings>(request, Wire.Json)!;
        Assert.True(settings.MonitorEnabled);
        Assert.Equal("headphones", settings.MonitorOutputId);
        Assert.Equal(.4f, settings.MonitorVolume);
    }

    static readonly List<DeviceInfo> Devices = [new("", "Default"), new("cable", "CABLE Input"), new("headphones", "Headphones")];
    static SavedState State => new(1, [], [], "cable", .75f, [], MonitorEnabled: true, MonitorOutputId: "headphones", MonitorVolume: .4f);

    [Fact]
    public void LegacyVolumeChangesPreserveHeadphoneSettings()
    {
        var request = JsonSerializer.Deserialize<AudioSettings>("""{"outputId":"cable","volume":0.2}""", Wire.Json)!;
        var saved = AudioRouting.Apply(State, request, Devices);
        Assert.True(saved.MonitorEnabled);
        Assert.Equal("headphones", saved.MonitorOutputId);
        Assert.Equal(.4f, saved.MonitorVolume);
        Assert.Equal(.2f, saved.Volume);
    }

    [Fact]
    public void HeadphoneSettingsSurviveRestartAndDoNotChangeChatVolume()
    {
        var saved = AudioRouting.Apply(State, new("cable", .75f, true, "", .25f), Devices);
        var loaded = JsonSerializer.Deserialize<SavedState>(JsonSerializer.Serialize(saved, Wire.Json), Wire.Json)!;
        Assert.True(loaded.MonitorEnabled);
        Assert.Equal("", loaded.MonitorOutputId);
        Assert.Equal(.25f, loaded.MonitorVolume);
        Assert.Equal(.75f, loaded.Volume);
        Assert.Equal(State.Version + 1, loaded.Version);
    }

    [Fact]
    public void LegacySavedStateStartsWithMonitoringOff()
    {
        var loaded = JsonSerializer.Deserialize<SavedState>("""{"version":1,"decks":[],"clips":[],"outputId":"cable","volume":0.75,"apps":[]}""", Wire.Json)!;
        Assert.False(loaded.MonitorEnabled);
        Assert.Equal("", loaded.MonitorOutputId);
        Assert.Equal(.75f, loaded.MonitorVolume);
    }

    [Fact]
    public void DisconnectedHeadphonesCanBeDisabledWithoutLosingTheirSelection()
    {
        var unplugged = State with { MonitorOutputId = "unplugged" };
        Assert.Throws<ArgumentException>(() => AudioRouting.Apply(unplugged, new("cable", .75f, true), Devices));
        var disabled = AudioRouting.Apply(unplugged, new("cable", .75f, false), Devices);
        Assert.False(disabled.MonitorEnabled);
        Assert.Equal("unplugged", disabled.MonitorOutputId);
    }

    [Theory]
    [InlineData(-.1f)]
    [InlineData(1.1f)]
    [InlineData(float.NaN)]
    [InlineData(float.PositiveInfinity)]
    public void InvalidHeadphoneVolumesAreRejected(float volume)
    {
        Assert.Throws<ArgumentException>(() => AudioRouting.Apply(State, new("cable", .75f, MonitorVolume: volume), Devices));
    }
}
