using Riff.Companion;
using Riff.Core;
using Xunit;

namespace Riff.WindowsTests;

public class ActionFeatureTests
{
    [Fact] public async Task StopButtonCancelsSwitchWhileActionGateIsOccupied()
    {
        var folder = Path.Combine(Path.GetTempPath(), "riff-actions-" + Guid.NewGuid().ToString("N"));
        try
        {
            var store = new StateStore(folder);
            using var audio = new AudioEngine();
            using var runner = new ActionRunner(store, audio);
            runner.SetSoundboardOnly(false);
            var pad = new Pad("switch", "Switch", "switch.2", "orange", "switch", "",
                [new("text", "Must never type", 5000)], [new("text", "Must never type", 5000)]);
            store.UpdateDecks(new(store.State.Version, [new("deck", "Deck", "folder", [pad])]));
            var pending = runner.Run(pad);
            await runner.Run(new("stop", "Stop", "stop.fill", "orange", "stop", "", []));
            await Assert.ThrowsAnyAsync<OperationCanceledException>(() => pending);
            Assert.Empty(runner.SwitchStatus().PadIds);
        }
        finally { if (Directory.Exists(folder)) Directory.Delete(folder, true); }
    }

    [Fact] public async Task HoldStopBypassesBusySequenceAndGestureAppReferencesPreventDeletion()
    {
        var folder = Path.Combine(Path.GetTempPath(), "riff-gestures-" + Guid.NewGuid().ToString("N"));
        try
        {
            var store = new StateStore(folder);
            using var audio = new AudioEngine();
            using var runner = new ActionRunner(store, audio);
            runner.SetSoundboardOnly(false);
            store.Save(store.State with { Apps = [new("app", "Test", @"C:\Test.exe")] });
            var pad = new Pad("gestures", "Controls", "hand.tap", "purple", "macro", "",
                [new("text", "Must never type", 5000)], DoubleTapAction: new("app", "app"), HoldAction: new("stop", ""));
            store.UpdateDecks(new(store.State.Version, [new("deck", "Deck", "folder", [pad])]));
            Assert.Throws<ArgumentException>(() => store.RemoveApp("app"));
            var pending = runner.Run(pad);
            await runner.Run(pad, gesture: "hold");
            await Assert.ThrowsAnyAsync<OperationCanceledException>(() => pending);
            runner.SetSoundboardOnly(true);
            await Assert.ThrowsAsync<ArgumentException>(() => runner.Run(pad, gesture: "doubleTap"));
            await runner.Run(pad, gesture: "hold");
        }
        finally { if (Directory.Exists(folder)) Directory.Delete(folder, true); }
    }

    [Fact] public void CannotRemoveAppUsedBySecondSequenceOrSmartProfile()
    {
        var folder = Path.Combine(Path.GetTempPath(), "riff-links-" + Guid.NewGuid().ToString("N"));
        try
        {
            var store = new StateStore(folder);
            store.Save(store.State with { Apps = [new("app", "Test", "C:\\Test.exe")] });
            var pad = new Pad("switch", "Switch", "switch.2", "orange", "switch", "",
                [new("text", "First")], [new("app", "app")]);
            store.UpdateDecks(new(store.State.Version, [new("deck", "Deck", "folder", [pad])]));
            Assert.Throws<ArgumentException>(() => store.RemoveApp("app"));
            store.UpdateDecks(new(store.State.Version, [new("deck", "Deck", "folder", [], LinkedAppId: "app")]));
            Assert.Throws<ArgumentException>(() => store.RemoveApp("app"));
            store.UpdateDecks(new(store.State.Version, [new("deck", "Deck", "folder", [])]));
            store.RemoveApp("app");
            Assert.Empty(store.State.Apps);
        }
        finally { if (Directory.Exists(folder)) Directory.Delete(folder, true); }
    }
}
