using System.Text.Json;
using System.Text.Json.Serialization;

namespace Riff.Core;

public record ActionStep(string Kind, string Value, int DelayMs = 0);
public record Pad(string Id, string Title, string Icon, string Color, string Kind, string Value, List<ActionStep> Steps);
public record Deck(string Id, string Name, string Icon, List<Pad> Pads, string SteamAppId = "");
public record Clip(string Id, string Name, double Duration);
public record LaunchTarget(string Id, string Name, string Path);
public record DeviceInfo(string Id, string Name);
public record Snapshot(int Version, List<Deck> Decks, List<Clip> Clips, List<DeviceInfo> Outputs,
    string OutputId, float Volume, List<LaunchTargetInfo> Apps, string ComputerName, List<SteamGame> Games, string ActiveGameId, string ActiveGameName);
public record SteamGame(string Id, string Name);
public record LaunchTargetInfo(string Id, string Name);
public record DeckUpdate(int Version, List<Deck> Decks);
public record Trigger(string PadId, string RequestId);
public record AudioSettings(string OutputId, float Volume);
public record SavedState(int Version, List<Deck> Decks, List<Clip> Clips, string OutputId, float Volume, List<LaunchTarget> Apps);

public static class Wire
{
    public static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
    {
        UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow
    };
}

public static class Rules
{
    public static readonly HashSet<string> Kinds = ["sound", "hotkey", "text", "url", "app", "media", "macro"];
    public static readonly HashSet<string> Media = ["playPause", "next", "previous", "volumeUp", "volumeDown", "mute"];
    public static void ValidateDecks(List<Deck> decks, IReadOnlySet<string> clips, IReadOnlySet<string> apps)
    {
        if (decks is null || decks.Count is < 1 or > 20) throw new ArgumentException("Keep between 1 and 20 decks.");
        var ids = new HashSet<string>();
        var linkedGames = new HashSet<string>();
        foreach (var deck in decks)
        {
            CheckId(deck.Id, ids);
            CheckText(deck.Name, 40, "Deck name");
            CheckText(deck.Icon, 80, "Icon");
            if (deck.SteamAppId is null || deck.SteamAppId.Length > 12 || !deck.SteamAppId.All(char.IsAsciiDigit)) throw new ArgumentException("Invalid Steam game ID.");
            if (deck.SteamAppId.Length > 0 && !linkedGames.Add(deck.SteamAppId)) throw new ArgumentException("This Steam game is already linked to another deck.");
            if (deck.Pads is null || deck.Pads.Count > 48) throw new ArgumentException("A deck can hold up to 48 buttons.");
            foreach (var pad in deck.Pads)
            {
                CheckId(pad.Id, ids);
                CheckText(pad.Title, 40, "Button name");
                CheckText(pad.Icon, 80, "Icon");
                if (pad.Color is not ("orange" or "purple" or "blue" or "green" or "pink")) throw new ArgumentException("Unknown button color.");
                ValidateAction(pad.Kind, pad.Value, clips, apps);
                if (pad.Steps is null || pad.Steps.Count > 20) throw new ArgumentException("Use at most 20 sequence steps.");
                if (pad.Kind == "macro")
                {
                    if (pad.Steps.Count == 0) throw new ArgumentException("Add a sequence step.");
                    foreach (var step in pad.Steps)
                    {
                        if (step.Kind == "macro") throw new ArgumentException("Sequences cannot contain sequences.");
                        if (step.DelayMs is < 0 or > 5000) throw new ArgumentException("Step delays must be 0-5000 ms.");
                        ValidateAction(step.Kind, step.Value, clips, apps);
                    }
                    if (pad.Steps.Sum(s => s.DelayMs) > 30000) throw new ArgumentException("Sequence delays cannot exceed 30 seconds.");
                }
                else if (pad.Steps.Count != 0) throw new ArgumentException("Only sequences can have steps.");
            }
        }
    }
    static void ValidateAction(string kind, string value, IReadOnlySet<string> clips, IReadOnlySet<string> apps)
    {
        if (!Kinds.Contains(kind) || value is null) throw new ArgumentException("Unknown action.");
        switch (kind)
        {
            case "sound" when !clips.Contains(value): throw new ArgumentException("Choose a sound from the library.");
            case "app" when !apps.Contains(value): throw new ArgumentException("Allow this app in the Windows companion first.");
            case "media" when !Media.Contains(value): throw new ArgumentException("Unknown media control.");
            case "hotkey": Hotkeys.Parse(value); break;
            case "text": CheckText(value, 2000, "Text"); break;
            case "url":
                if (value.Length > 2048 || !Uri.TryCreate(value, UriKind.Absolute, out var uri) || uri.Scheme is not ("http" or "https"))
                    throw new ArgumentException("Use a full http or https website address.");
                break;
        }
    }
    static void CheckId(string id, HashSet<string> ids)
    {
        if (string.IsNullOrWhiteSpace(id) || id.Length > 80 || !ids.Add(id)) throw new ArgumentException("Deck and button IDs must be unique.");
    }
    public static void CheckText(string text, int limit, string label)
    {
        if (string.IsNullOrWhiteSpace(text) || text.Length > limit) throw new ArgumentException($"{label} must be 1-{limit} characters.");
    }
}

public static class Hotkeys
{
    static readonly Dictionary<string, ushort> Named = new(StringComparer.OrdinalIgnoreCase)
    {
        ["CTRL"] = 0x11, ["ALT"] = 0x12, ["SHIFT"] = 0x10, ["WIN"] = 0x5B,
        ["ENTER"] = 0x0D, ["SPACE"] = 0x20, ["TAB"] = 0x09, ["ESC"] = 0x1B,
        ["BACKSPACE"] = 0x08, ["DELETE"] = 0x2E, ["UP"] = 0x26, ["DOWN"] = 0x28,
        ["LEFT"] = 0x25, ["RIGHT"] = 0x27, ["HOME"] = 0x24, ["END"] = 0x23,
        ["PAGEUP"] = 0x21, ["PAGEDOWN"] = 0x22, ["INSERT"] = 0x2D
    };
    public static ushort[] Parse(string value)
    {
        if (string.IsNullOrWhiteSpace(value) || value.Length > 100) throw new ArgumentException("Enter a shortcut such as Ctrl+Shift+M.");
        var parts = value.Split('+', StringSplitOptions.TrimEntries);
        if (parts.Length > 5) throw new ArgumentException("Use at most five keys in a shortcut.");
        var keys = parts.Select(part =>
        {
            if (Named.TryGetValue(part, out var key)) return key;
            if (part.Length == 1 && char.IsAsciiLetterOrDigit(part[0])) return (ushort)char.ToUpperInvariant(part[0]);
            if (part.StartsWith('F') && int.TryParse(part.AsSpan(1), out var f) && f is >= 1 and <= 24) return (ushort)(0x6F + f);
            throw new ArgumentException($"Unknown key '{part}'. Use letters, digits, F1-F24, or named keys such as Space.");
        }).ToArray();
        if (keys.Distinct().Count() != keys.Length) throw new ArgumentException("Do not repeat a key in a shortcut.");
        return keys;
    }
}

public static class Defaults
{
    public static List<Deck> Decks => [
        new("soundboard", "Soundboard", "waveform", [
            new("level-up-pad", "Level up", "sparkles", "orange", "sound", "level-up", []),
            new("plot-twist-pad", "Plot twist", "theatermasks", "purple", "sound", "plot-twist", []),
            new("nope-pad", "Nope", "hand.raised", "pink", "sound", "nope", []),
            new("countdown-pad", "Countdown", "timer", "blue", "sound", "countdown", []),
            new("coin-drop-pad", "Coin drop", "circle.circle", "green", "sound", "coin-drop", []),
            new("red-alert-pad", "Red alert", "light.beacon.max", "orange", "sound", "red-alert", [])]),
        new("everyday", "Everyday", "command", [
            new("play-pause-pad", "Play / pause", "playpause", "green", "media", "playPause", []),
            new("next-pad", "Next track", "forward.end", "blue", "media", "next", []),
            new("mute-pad", "Mute audio", "speaker.slash", "pink", "media", "mute", []),
            new("desktop-pad", "Show desktop", "desktopcomputer", "purple", "hotkey", "Win+D", []),
            new("screenshot-pad", "Screenshot", "viewfinder", "orange", "hotkey", "Win+Shift+S", []),
            new("gg-pad", "Good game", "text.bubble", "green", "text", "gg, well played!", [])])
    ];
}
