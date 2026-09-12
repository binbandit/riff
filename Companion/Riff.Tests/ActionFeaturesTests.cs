using System.Text.Json;
using Riff.Core;
using Xunit;

namespace Riff.Tests;

public class ActionFeaturesTests
{
    static Pad Switch => new("switch", "Stream", "switch.2", "orange", "switch", "",
        [new("text", "start"), new("hotkey", "Ctrl+M")], [new("text", "end")]);
    static List<Deck> Decks(Pad pad) => [new("deck", "Deck", "folder", [pad])];
    static void Validate(Pad pad) => Rules.ValidateDecks(Decks(pad), new HashSet<string>(), new HashSet<string>());

    [Fact] public async Task SwitchAlternatesOnlyAfterCompleteSuccess()
    {
        var engine = new ActionSequences();
        var seen = new List<string>();
        Task Execute(ActionStep step, CancellationToken _) { seen.Add(step.Value); return Task.CompletedTask; }
        await engine.Run(Switch, Execute, default);
        Assert.Equal(new[] { "start", "Ctrl+M" }, seen);
        Assert.Contains("switch", engine.Status([Switch]).PadIds);
        await Assert.ThrowsAsync<IOException>(() => engine.Run(Switch, (_, _) => throw new IOException(), default));
        Assert.Contains("switch", engine.Status([Switch]).PadIds);
        await engine.Run(Switch, Execute, default);
        Assert.Equal("end", seen.Last());
        Assert.Empty(engine.Status([Switch]).PadIds);
    }

    [Fact] public async Task StopPreventsLaterStepsAndDoesNotAdvanceSwitch()
    {
        var engine = new ActionSequences();
        using var cancellation = new CancellationTokenSource();
        var seen = 0;
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => engine.Run(Switch, (_, _) =>
        {
            seen++; cancellation.Cancel(); return Task.CompletedTask;
        }, cancellation.Token));
        Assert.Equal(1, seen);
        Assert.Empty(engine.Status([Switch]).PadIds);
    }

    [Fact] public async Task RandomRunsExactlyOneSelectedChoice()
    {
        var engine = new ActionSequences();
        var pad = Switch with { Kind = "random", AlternateSteps = null };
        for (var index = 0; index < pad.Steps.Count; index++)
        {
            var seen = new List<string>();
            await engine.Run(pad, (step, _) => { seen.Add(step.Value); return Task.CompletedTask; }, default,
                count => { Assert.Equal(2, count); return index; });
            Assert.Equal(new[] { pad.Steps[index].Value }, seen);
        }
    }

    [Fact] public async Task EditingDeletingAndRestartingResetSwitchState()
    {
        var engine = new ActionSequences();
        await engine.Run(Switch, (_, _) => Task.CompletedTask, default);
        var before = engine.Status([Switch]);
        Assert.Contains("switch", before.PadIds);
        var edited = Switch with { Title = "Changed" };
        Assert.Empty(engine.Status([edited]).PadIds);
        Assert.True(engine.Status([edited]).Revision > before.Revision);
        await engine.Run(edited, (_, _) => Task.CompletedTask, default);
        Assert.Empty(engine.Status([]).PadIds);
        Assert.NotEqual(before.SessionId, new ActionSequences().Status([Switch]).SessionId);
    }

    [Fact] public void BothSidesAreValidatedAndContainersCannotNest()
    {
        Validate(Switch);
        foreach (var kind in new[] { "macro", "switch", "random", "deck", "back", "stop", "unknown" })
            Assert.Throws<ArgumentException>(() => Validate(Switch with { AlternateSteps = [new(kind, "deck")] }));
        Assert.Throws<ArgumentException>(() => Validate(Switch with { AlternateSteps = [] }));
        Assert.Throws<ArgumentException>(() => Validate(Switch with { AlternateSteps = [new("app", "unapproved")] }));
        Assert.Throws<ArgumentException>(() => Validate(Switch with { AlternateSteps = [new("sound", "missing")] }));
        Assert.Throws<ArgumentException>(() => Validate(Switch with { AlternateSteps = [new("text", "hello", -1)] }));
        Assert.Throws<ArgumentException>(() => Validate(Switch with { AlternateSteps = Enumerable.Repeat(new ActionStep("text", "hello", 5000), 7).ToList() }));
        Assert.Throws<ArgumentException>(() => Validate(Switch with { Kind = "random" }));
    }

    [Fact] public void NavigationReferencesAndSmartProfileLinksMustExistAndBeUnique()
    {
        Validate(Switch with { Kind = "deck", Value = "deck", Steps = [], AlternateSteps = null });
        Assert.Throws<ArgumentException>(() => Validate(Switch with { Kind = "deck", Value = "missing", Steps = [], AlternateSteps = null }));
        var decks = new List<Deck> { new("one", "One", "folder", [], LinkedAppId: "app"), new("two", "Two", "folder", []) };
        Rules.ValidateDecks(decks, new HashSet<string>(), new HashSet<string> { "app" });
        Assert.Throws<ArgumentException>(() => Rules.ValidateDecks(decks, new HashSet<string>(), new HashSet<string>()));
        decks[1] = decks[1] with { LinkedAppId = "app" };
        Assert.Throws<ArgumentException>(() => Rules.ValidateDecks(decks, new HashSet<string>(), new HashSet<string> { "app" }));
    }

    [Fact] public void PinnedButtonsRoundTripWithoutChangingTheirActions()
    {
        var pad = Switch with { Pinned = true };
        Validate(pad);
        var decoded = JsonSerializer.Deserialize<Pad>(JsonSerializer.Serialize(pad, Wire.Json), Wire.Json)!;
        Assert.True(decoded.Pinned);
        Assert.Equal(pad.Steps, decoded.Steps);
        Assert.Equal(pad.AlternateSteps, decoded.AlternateSteps);
    }

    [Fact] public void LegacyFilesRemainReadableAndSoundboardModeKeepsNavigationAndStop()
    {
        const string json = """{"id":"deck","name":"Deck","icon":"folder","pads":[{"id":"pad","title":"Text","icon":"text.bubble","color":"orange","kind":"text","value":"Hi","steps":[]}],"steamAppId":""}""";
        var deck = JsonSerializer.Deserialize<Deck>(json, Wire.Json)!;
        Assert.Null(deck.LinkedAppId);
        Assert.Null(deck.Pads[0].AlternateSteps);
        Assert.False(deck.Pads[0].Pinned);
        foreach (var kind in new[] { "deck", "back", "stop" }) SoundboardPolicy.EnsureAllowed(kind, true);
        foreach (var kind in new[] { "switch", "random", "macro" })
            Assert.Throws<ArgumentException>(() => SoundboardPolicy.EnsureAllowed(kind, true));
    }
}
