namespace Riff.Core;

public record ActiveSound(string Id, string PadId);
public record PlaybackPlan(bool Start, List<string> StopIds);

public static class PlaybackPolicy
{
    public static PlaybackPlan Plan(IReadOnlyList<ActiveSound> playing, string padId, bool toggle, string mode)
    {
        if (mode is not ("overlap" or "single")) throw new ArgumentException("Choose Overlap or One at a time.");
        var matching = playing.Where(p => padId.Length > 0 && p.PadId == padId).Select(p => p.Id).ToList();
        if (toggle && matching.Count > 0) return new(false, matching);
        var stops = mode == "single" ? playing.Select(p => p.Id).ToList() : new List<string>();
        if (playing.Count - stops.Count >= 16) throw new ArgumentException("16 sounds are already playing. Stop a sound before starting another.");
        return new(true, stops);
    }
}
