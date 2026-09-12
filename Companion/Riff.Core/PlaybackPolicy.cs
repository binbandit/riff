namespace Riff.Core;

public record ActiveSound(string Id, string PadId);
public record PlaybackPlan(bool Start, List<string> StopIds, bool Enqueue = false, List<string>? RemoveQueuedIds = null);

public static class PlaybackPolicy
{
    public static PlaybackPlan Plan(IReadOnlyList<ActiveSound> playing, string padId, bool toggle, string mode, IReadOnlyList<ActiveSound>? queued = null)
    {
        if (mode is not ("overlap" or "single" or "queue")) throw new ArgumentException("Choose Overlap, One at a time, or Queue.");
        queued ??= [];
        var removeQueued = queued.Where(p => mode != "queue" || (toggle && padId.Length > 0 && p.PadId == padId)).Select(p => p.Id).ToList();
        var matching = playing.Where(p => padId.Length > 0 && p.PadId == padId).Select(p => p.Id).ToList();
        if (toggle && (matching.Count > 0 || (mode == "queue" && removeQueued.Count > 0)))
            return new(false, matching, RemoveQueuedIds: removeQueued);
        if (mode == "queue" && (playing.Count > 0 || queued.Count > 0))
        {
            if (queued.Count >= 48) throw new ArgumentException("48 sounds are already queued. Remove a sound or wait for one to finish.");
            return new(false, [], Enqueue: true, RemoveQueuedIds: []);
        }
        var stops = mode == "single" ? playing.Select(p => p.Id).ToList() : new List<string>();
        if (playing.Count - stops.Count >= 16) throw new ArgumentException("16 sounds are already playing. Stop a sound before starting another.");
        return new(true, stops, RemoveQueuedIds: removeQueued);
    }
}
