using System.Text.Json;
using Riff.Core;

namespace Riff.Companion;

internal sealed class AppearancePreferences
{
    readonly string path;
    readonly object gate = new();
    CompanionAppearance current = new();
    public CompanionAppearance Current { get { lock (gate) return current; } }

    public AppearancePreferences(string folder)
    {
        path = Path.Combine(folder, "appearance.json");
        try
        {
            if (JsonSerializer.Deserialize<CompanionAppearance>(File.ReadAllText(path)) is { } saved)
                current = CompanionAppearance.Parse(saved.Theme, saved.Dark ? "dark" : "light") ?? new();
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or JsonException) { }
    }

    public void Update(CompanionAppearance appearance)
    {
        lock (gate)
        {
            if (current == appearance) return;
            current = appearance;
            File.WriteAllText(path + ".tmp", JsonSerializer.Serialize(appearance));
            File.Move(path + ".tmp", path, overwrite: true);
        }
    }
}
