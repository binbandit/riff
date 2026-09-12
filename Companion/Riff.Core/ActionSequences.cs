using System.Text.Json;

namespace Riff.Core;

// The companion owns switch state so all paired iPads agree. Call Run under the action gate.
public sealed class ActionSequences
{
    readonly object gate = new();
    readonly Dictionary<string, (string Definition, bool Second)> switches = [];
    readonly string sessionId = Guid.NewGuid().ToString();
    long revision;

    public async Task Run(Pad pad, Func<ActionStep, CancellationToken, Task> execute, CancellationToken token,
        Func<int, int>? choose = null)
    {
        var definition = JsonSerializer.Serialize(pad, Wire.Json);
        bool second;
        lock (gate) second = switches.TryGetValue(pad.Id, out var saved) && saved.Definition == definition && saved.Second;
        IReadOnlyList<ActionStep> steps = pad.Kind switch
        {
            "macro" => pad.Steps,
            "switch" => second ? pad.AlternateSteps ?? [] : pad.Steps,
            "random" when pad.Steps.Count > 0 => [pad.Steps[(choose ?? Random.Shared.Next)(pad.Steps.Count)]],
            _ => throw new ArgumentException("Unknown or empty sequence.")
        };
        if (steps.Count == 0) throw new ArgumentException("Add a sequence step.");
        foreach (var step in steps)
        {
            await Task.Delay(step.DelayMs, token);
            token.ThrowIfCancellationRequested();
            await execute(step, token);
        }
        token.ThrowIfCancellationRequested();
        if (pad.Kind == "switch")
            lock (gate) { switches[pad.Id] = (definition, !second); revision++; }
    }

    public PlaybackState Status(IEnumerable<Pad> pads)
    {
        var definitions = pads.Where(p => p.Kind == "switch").ToDictionary(p => p.Id, p => JsonSerializer.Serialize(p, Wire.Json));
        lock (gate)
        {
            foreach (var id in switches.Keys.ToArray())
                if (!definitions.TryGetValue(id, out var definition) || switches[id].Definition != definition)
                { switches.Remove(id); revision++; }
            return new(sessionId, revision, switches.Where(p => p.Value.Second).Select(p => p.Key).Order().ToList());
        }
    }
}
