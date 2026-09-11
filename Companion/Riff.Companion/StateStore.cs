using System.Text.Json;
using NAudio.Wave;
using Riff.Core;

namespace Riff.Companion;

public sealed class StateStore
{
    public readonly object Gate = new();
    public string Folder { get; }
    public SavedState State { get; private set; }
    string StatePath => Path.Combine(Folder, "state.json");
    public StateStore(string folder)
    {
        Folder = folder;
        Directory.CreateDirectory(Path.Combine(folder, "clips"));
        if (File.Exists(StatePath))
            State = JsonSerializer.Deserialize<SavedState>(File.ReadAllText(StatePath), Wire.Json) ?? throw new InvalidDataException("Cannot read saved decks. Restore state.json from a backup.");
        else
        {
            var clips = new List<Clip>();
            foreach (var file in Directory.GetFiles(Path.Combine(AppContext.BaseDirectory, "Sounds"), "*.wav"))
            {
                var id = Path.GetFileNameWithoutExtension(file);
                File.Copy(file, ClipPath(id), true);
                using var reader = new WaveFileReader(file);
                clips.Add(new(id, System.Globalization.CultureInfo.InvariantCulture.TextInfo.ToTitleCase(id.Replace('-', ' ')), reader.TotalTime.TotalSeconds));
            }
            State = new(1, Defaults.Decks, clips, "", 0.75f, []);
            Save(State);
        }
        Rules.ValidateDecks(State.Decks, State.Clips.Select(c => c.Id).ToHashSet(), State.Apps.Select(a => a.Id).ToHashSet());
    }
    public string ClipPath(string id) => Path.Combine(Folder, "clips", id + ".wav");
    public void Save(SavedState next)
    {
        // Write first so a failed save never appears successful to a client.
        var temp = StatePath + ".tmp";
        File.WriteAllText(temp, JsonSerializer.Serialize(next, Wire.Json));
        File.Move(temp, StatePath, true);
        State = next;
    }
    public void UpdateDecks(DeckUpdate update)
    {
        lock (Gate)
        {
            if (update.Version != State.Version) throw new StateConflictException();
            Rules.ValidateDecks(update.Decks, State.Clips.Select(c => c.Id).ToHashSet(), State.Apps.Select(a => a.Id).ToHashSet());
            Save(State with { Decks = update.Decks, Version = State.Version + 1 });
        }
    }
    public void AddApp(string path)
    {
        if (!File.Exists(path) || !Path.GetExtension(path).Equals(".exe", StringComparison.OrdinalIgnoreCase)) throw new ArgumentException("Choose an existing Windows .exe application.");
        lock (Gate)
        {
            if (State.Apps.Any(a => a.Path.Equals(path, StringComparison.OrdinalIgnoreCase))) return;
            Save(State with { Apps = [.. State.Apps, new(Guid.NewGuid().ToString("N"), Path.GetFileNameWithoutExtension(path), path)], Version = State.Version + 1 });
        }
    }
    public void RemoveApp(string id)
    {
        lock (Gate)
        {
            if (State.Decks.SelectMany(d => d.Pads).Any(p => (p.Kind == "app" && p.Value == id) || p.Steps.Any(s => s.Kind == "app" && s.Value == id)))
                throw new ArgumentException("Remove buttons using this app from your decks first.");
            Save(State with { Apps = State.Apps.Where(a => a.Id != id).ToList(), Version = State.Version + 1 });
        }
    }
}
public sealed class StateConflictException : Exception
{
    public StateConflictException() : base("Your decks changed on another device. The latest version has been loaded; try your edit again.") { }
}
