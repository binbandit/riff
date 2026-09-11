using System.Text.Json;
using Riff.Core;
using Xunit;

namespace Riff.Tests;

public class DeckRulesTests
{
    static readonly HashSet<string> Clips = ["level-up", "plot-twist", "nope", "countdown", "coin-drop", "red-alert"];
    static List<Deck> With(Pad pad) => [new("deck", "Test", "waveform", [pad])];
    static Pad Sound => new("pad", "Sound", "waveform", "orange", "sound", "level-up", []);
    [Fact] public void StarterDecksAreValidAndWireRoundTrips()
    {
        var decks = Defaults.Decks;
        Rules.ValidateDecks(decks, Clips, new HashSet<string>());
        var json = JsonSerializer.Serialize(new DeckUpdate(1, decks), Wire.Json);
        var decoded = JsonSerializer.Deserialize<DeckUpdate>(json, Wire.Json)!;
        Rules.ValidateDecks(decoded.Decks, Clips, new HashSet<string>());
        Assert.Equal(12, decoded.Decks.Sum(d => d.Pads.Count));
        Assert.Contains("\"steamAppId\":\"\"", json);
    }
    [Theory]
    [InlineData("file:///C:/Windows/System32/cmd.exe")]
    [InlineData("javascript:alert(1)")]
    [InlineData("shell:AppsFolder")]
    [InlineData("ftp://example.com")]
    public void WebsiteActionsCannotLaunchLocalPrograms(string value) => Assert.Throws<ArgumentException>(() => Rules.ValidateDecks(With(Sound with { Kind = "url", Value = value }), Clips, new HashSet<string>()));
    [Fact] public void ApplicationsMustBeApprovedLocally()
    {
        var decks = With(Sound with { Kind = "app", Value = "unapproved" });
        Assert.Throws<ArgumentException>(() => Rules.ValidateDecks(decks, Clips, new HashSet<string>()));
        Rules.ValidateDecks(decks, Clips, new HashSet<string> { "unapproved" });
    }
    [Fact] public void ClipReferencesCannotBePaths() => Assert.Throws<ArgumentException>(() => Rules.ValidateDecks(With(Sound with { Value = "../../secret" }), Clips, new HashSet<string>()));
    [Fact] public void DuplicateIdsAcrossDecksAreRejected()
    {
        var decks = With(Sound); decks.Add(new("second", "Second", "waveform", [Sound]));
        Assert.Throws<ArgumentException>(() => Rules.ValidateDecks(decks, Clips, new HashSet<string>()));
    }
    [Fact] public void SequencesAreBoundedAndCannotNest()
    {
        var pad = Sound with { Kind = "macro", Value = "", Steps = [new("macro", "")] };
        Assert.Throws<ArgumentException>(() => Rules.ValidateDecks(With(pad), Clips, new HashSet<string>()));
        pad = pad with { Steps = Enumerable.Repeat(new ActionStep("sound", "level-up", 5000), 7).ToList() };
        Assert.Throws<ArgumentException>(() => Rules.ValidateDecks(With(pad), Clips, new HashSet<string>()));
        pad = pad with { Steps = [new("hotkey", "Ctrl+Shift+M"), new("sound", "level-up", 200)] };
        Rules.ValidateDecks(With(pad), Clips, new HashSet<string>());
    }
    [Theory]
    [InlineData("Ctrl+Ctrl+A")]
    [InlineData("Ctrl++A")]
    [InlineData("F25")]
    [InlineData("powershell.exe")]
    public void InvalidHotkeysAreRejected(string value) => Assert.Throws<ArgumentException>(() => Hotkeys.Parse(value));
    [Fact] public void HotkeysMapToWindowsVirtualKeys() => Assert.Equal(new ushort[] { 0x11, 0x10, 0x4D }, Hotkeys.Parse("Ctrl+Shift+M"));
    [Fact] public void UnknownFieldsAreRejected() => Assert.Throws<JsonException>(() => JsonSerializer.Deserialize<Trigger>("{\"padId\":\"a\",\"requestId\":\"b\",\"command\":\"cmd.exe\"}", Wire.Json));
    [Fact] public void MissingRequiredTextFailsValidation() => Assert.Throws<ArgumentException>(() => Rules.ValidateDecks(With(Sound with { Title = null! }), Clips, new HashSet<string>()));
    [Fact] public void AGameCannotBeLinkedToTwoDecks()
    {
        var decks = Defaults.Decks.Select(d => d with { SteamAppId = "730" }).ToList();
        Assert.Throws<ArgumentException>(() => Rules.ValidateDecks(decks, Clips, new HashSet<string>()));
    }
    [Fact] public void LastDeckCannotBeDeleted() => Assert.Throws<ArgumentException>(() => Rules.ValidateDecks([], Clips, new HashSet<string>()));
    [Fact] public void ReorderingPreservesActionBindings()
    {
        var decks = Defaults.Decks;
        var pad = decks[0].Pads[0]; decks[0].Pads.RemoveAt(0); decks[0].Pads.Insert(4, pad);
        var copy = JsonSerializer.Deserialize<DeckUpdate>(JsonSerializer.Serialize(new DeckUpdate(2, decks), Wire.Json), Wire.Json)!;
        Assert.Equal("level-up", copy.Decks[0].Pads[4].Value); Assert.Equal(pad.Id, copy.Decks[0].Pads[4].Id);
    }
}
