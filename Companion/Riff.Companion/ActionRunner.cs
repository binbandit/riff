using System.Diagnostics;
using Riff.Core;

namespace Riff.Companion;

public sealed class ActionRunner(StateStore store, AudioEngine audio) : IDisposable
{
    readonly SemaphoreSlim actionGate = new(1, 1);
    readonly object cancelGate = new();
    CancellationTokenSource cancellation = new();
    public async Task Run(Pad pad, bool toggle = false, string? soundMode = null)
    {
        if (soundMode is not (null or "overlap" or "single")) throw new ArgumentException("Choose Overlap or One at a time.");
        lock (cancelGate)
            lock (store.Gate) SoundboardPolicy.EnsureAllowed(pad.Kind, store.State.SoundboardOnly);
        if (pad.Kind == "sound")
        {
            lock (cancelGate) Execute(pad.Kind, pad.Value, cancellation.Token, pad.Id == "preview" ? "" : pad.Id, toggle, soundMode);
            return;
        }
        if (!await actionGate.WaitAsync(0)) throw new ArgumentException("An action sequence is running. Stop it or wait for it to finish.");
        CancellationToken token;
        lock (cancelGate) token = cancellation.Token;
        try
        {
            if (pad.Kind == "macro")
            {
                foreach (var step in pad.Steps)
                {
                    await Task.Delay(step.DelayMs, token);
                    Execute(step.Kind, step.Value, token);
                }
            }
            else Execute(pad.Kind, pad.Value, token);
        }
        finally { actionGate.Release(); }
    }
    void Execute(string kind, string value, CancellationToken token, string padId = "", bool toggle = false, string? mode = null)
    {
        // Serialize cancellation with starting an action so Stop All cannot be overtaken by a late sound.
        lock (cancelGate)
        {
            token.ThrowIfCancellationRequested();
            lock (store.Gate) SoundboardPolicy.EnsureAllowed(kind, store.State.SoundboardOnly);
            switch (kind)
            {
                case "sound":
                    lock (store.Gate)
                    {
                        if (!store.State.Clips.Any(c => c.Id == value)) throw new ArgumentException("This sound no longer exists.");
                        audio.Play(store.ClipPath(value), store.State.OutputId, padId, toggle, mode);
                    }
                    break;
                case "hotkey": WindowsInput.Hotkey(value); break;
                case "text": WindowsInput.Text(value); break;
                case "media": WindowsInput.Media(value); break;
                case "url": Process.Start(new ProcessStartInfo(value) { UseShellExecute = true }); break;
                case "app":
                    LaunchTarget? target;
                    lock (store.Gate) target = store.State.Apps.FirstOrDefault(a => a.Id == value);
                    if (target is null) throw new ArgumentException("This app is not allowed on the PC.");
                    Process.Start(new ProcessStartInfo(target.Path) { UseShellExecute = true }); break;
                default: throw new ArgumentException("Unknown action.");
            }
        }
    }
    public void SetSoundboardOnly(bool enabled)
    {
        lock (cancelGate)
        {
            lock (store.Gate)
            {
                if (store.State.SoundboardOnly == enabled) return;
                store.Save(store.State with { SoundboardOnly = enabled, Version = store.State.Version + 1 });
            }
            // Cancel waiting sequence steps before releasing the same gate used to execute them.
            cancellation.Cancel(); cancellation.Dispose(); cancellation = new();
        }
    }
    public void Stop()
    {
        lock (cancelGate) { cancellation.Cancel(); cancellation.Dispose(); cancellation = new(); audio.StopAll(); }
    }
    public void Dispose() { Stop(); cancellation.Dispose(); actionGate.Dispose(); }
}
