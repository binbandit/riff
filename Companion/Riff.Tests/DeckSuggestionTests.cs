using System.Text.Json;
using Riff.Core;
using Xunit;

namespace Riff.Tests;

public class DeckSuggestionTests
{
    static SavedState State(bool soundboard = true) => new(1,
        [new("deck", "Existing", "waveform", [new("shortcut", "Mute microphone", "mic", "blue", "hotkey", "Ctrl+Shift+M", [])])],
        [new("clip", "Air horn", 1)], "default", 1, [new("app", "Discord", @"C:\private\Discord.exe")], soundboard);

    static string Response(params DeckSuggestions.Choice[] choices) => JsonSerializer.Serialize(new
    {
        status = "completed", output = new[] { new { type = "message", content = new[] { new
        {
            type = "output_text", text = JsonSerializer.Serialize(new DeckSuggestions.Proposal("Game night", "gamecontroller", "A mix of reactions.", choices.ToList()), Wire.Json)
        } } } }
    });

    [Fact]
    public void ContextContainsSelectedGameAndCatalogWithoutPrivateActionsOrPaths()
    {
        var state = State(false);
        var options = DeckSuggestions.Options(state);
        var context = DeckSuggestions.Context(new("730", "app", "", "Funny reactions"), [new("730", "Counter-Strike 2")], state.Apps, options);
        Assert.Contains("Counter-Strike 2", context); Assert.Contains("Discord", context); Assert.Contains("Air horn", context);
        Assert.DoesNotContain("private", context); Assert.DoesNotContain("Ctrl+Shift+M", context);
        Assert.DoesNotContain(options, o => o.PackId != null);
        Assert.Equal(options.Count, options.Select(o => o.Id).Distinct().Count());
    }

    [Fact]
    public void SoundboardModeExcludesDesktopActionsAndInstalledPacksAreNotDuplicated()
    {
        var state = State();
        var sound = SoundPacks.Catalog[0].Sounds[0];
        state.Clips.Add(new(sound.ClipId, "My renamed sound", sound.Duration));
        var options = DeckSuggestions.Options(state);
        Assert.All(options, o => Assert.Contains(o.Pad.Kind, new[] { "sound", "stop" }));
        var installed = Assert.Single(options, o => o.Pad.Value == sound.ClipId);
        Assert.Null(installed.PackId); Assert.Contains("My renamed sound", installed.Description);
    }

    [Fact]
    public void ModelCanChooseAndStyleAnExistingActionButCannotInventOne()
    {
        var options = DeckSuggestions.Options(State(false));
        var original = options.First(o => o.Pad.Kind == "hotkey");
        var choice = new DeckSuggestions.Choice(original.Id, "Mic toggle", "mic", "blue", "Keep team comms handy.");
        var result = DeckSuggestions.Parse(Response(choice), options);
        var button = Assert.Single(result.Buttons);
        Assert.Equal("Ctrl+Shift+M", button.Pad.Value); Assert.Equal("hotkey", button.Pad.Kind);
        Assert.NotEqual(original.Pad.Id, button.Pad.Id); Assert.Equal("Mic toggle", button.Pad.Title);
        Assert.ThrowsAny<Exception>(() => DeckSuggestions.Parse(Response(choice with { OptionId = "invented" }), options));
        Assert.ThrowsAny<Exception>(() => DeckSuggestions.Parse(Response(choice, choice), options));
        Assert.ThrowsAny<Exception>(() => DeckSuggestions.Parse(Response(choice with { Icon = "invalid" }), options));
        Assert.ThrowsAny<Exception>(() => DeckSuggestions.Parse(Response(choice with { Label = new string('x', 41) }), options));
        Assert.ThrowsAny<Exception>(() => DeckSuggestions.Parse(Response(), options));
    }

    [Fact]
    public void PackMetadataComesFromTheCatalogAndRequestsAreBounded()
    {
        var state = SoundPacks.Populate(State()); var options = DeckSuggestions.Options(state);
        var option = options.First(o => o.Pad.Value.StartsWith("pack-"));
        var result = DeckSuggestions.Parse(Response(new DeckSuggestions.Choice(option.Id, "Reaction", "waveform", "orange", "A quick reaction.")), options);
        var button = Assert.Single(result.Buttons);
        Assert.Equal(option.PackId, button.PackId); Assert.Equal(option.SoundId, button.SoundId); Assert.Equal(option.Pad.Value, button.Pad.Value);
        Assert.Throws<ArgumentException>(() => DeckSuggestions.Context(new("", "", "", ""), [], [], options));
        Assert.Throws<ArgumentException>(() => DeckSuggestions.Context(new("730", "", "", new string('x', 501)), [], [], options));
    }
}
