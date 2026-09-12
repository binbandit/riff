using System.Text.Json;
using Riff.Core;
using Xunit;

namespace Riff.Tests;

public class KeyLogicTests
{
    static Pad Button => new("pad", "Controls", "hand.tap", "purple", "text", "Tap", [],
        DoubleTapAction: new("sound", "sound"), HoldAction: new("deck", "deck"));
    static void Validate(Pad pad) => Rules.ValidateDecks([new("deck", "Deck", "folder", [pad])], new HashSet<string> { "sound" }, new HashSet<string> { "app" });

    [Fact] public void EachGestureResolvesExactlyItsStoredAction()
    {
        var pad = Button;
        Assert.Same(pad, pad.Resolve(null));
        Assert.Same(pad, pad.Resolve("tap"));
        Assert.Equal("sound", pad.Resolve("doubleTap").Kind);
        Assert.Equal("deck", pad.Resolve("hold").Kind);
        Assert.Equal(pad.Id, pad.Resolve("doubleTap").Id);
        Assert.Throws<ArgumentException>(() => pad.Resolve("unknown"));
        Assert.Throws<ArgumentException>(() => (pad with { HoldAction = null }).Resolve("hold"));
        Assert.Empty(pad.Resolve("doubleTap").GestureActions);
    }

    [Fact] public void BindingsValidateResourcesAndRejectContainersAndUnsafeActions()
    {
        Validate(Button);
        foreach (var action in new PadGestureAction[] { new("app", "missing"), new("sound", "missing"), new("deck", "missing"), new("url", "file:///secret"), new("hotkey", "NoKey"), new("media", "unknown"), new("text", ""), new("macro", ""), new("switch", ""), new("random", "") })
        {
            Assert.Throws<ArgumentException>(() => Validate(Button with { DoubleTapAction = action }));
            Assert.Throws<ArgumentException>(() => Validate(Button with { HoldAction = action }));
        }
        Assert.True(Button.Uses("sound", "sound"));
        Assert.True((Button with { HoldAction = new("app", "app") }).Uses("app", "app"));
        Assert.False(Button.Uses("sound", "missing"));
    }

    [Fact] public void SoundboardPolicyUsesSelectedGesture()
    {
        Assert.Throws<ArgumentException>(() => SoundboardPolicy.EnsureAllowed(Button.Resolve("tap").Kind, true));
        SoundboardPolicy.EnsureAllowed(Button.Resolve("doubleTap").Kind, true);
        SoundboardPolicy.EnsureAllowed(Button.Resolve("hold").Kind, true);
    }

    [Fact] public void WireRoundTripHasNoComputedFieldsAndLegacyTriggerDefaultsToTap()
    {
        var json = JsonSerializer.Serialize(Button, Wire.Json);
        Assert.DoesNotContain("gestureActions", json);
        var decoded = JsonSerializer.Deserialize<Pad>(json, Wire.Json)!;
        Assert.Equal(Button.DoubleTapAction, decoded.DoubleTapAction);
        Assert.Equal(Button.HoldAction, decoded.HoldAction);
        Assert.Null(JsonSerializer.Deserialize<Trigger>("""{"padId":"pad","requestId":"request"}""", Wire.Json)!.Gesture);
        Assert.Equal("hold", JsonSerializer.Deserialize<Trigger>("""{"padId":"pad","requestId":"request","gesture":"hold"}""", Wire.Json)!.Gesture);
    }
}
