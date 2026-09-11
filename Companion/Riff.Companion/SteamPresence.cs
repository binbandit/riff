using Microsoft.Win32;
using Riff.Core;
using System.Text.RegularExpressions;

namespace Riff.Companion;

public sealed partial class SteamPresence
{
    readonly object gate = new();
    List<SteamGame> games = [];
    DateTime nextScan;
    [GeneratedRegex("\"(?<key>[^\"]+)\"\\s*\"(?<value>(?:\\\\.|[^\"\\\\])*)\"", RegexOptions.CultureInvariant)]
    private static partial Regex Pairs();
    static IEnumerable<(string Key, string Value)> ReadPairs(string path)
    {
        if (!File.Exists(path) || new FileInfo(path).Length > 4 * 1024 * 1024) return [];
        return Pairs().Matches(File.ReadAllText(path)).Select(m => (m.Groups["key"].Value, m.Groups["value"].Value.Replace("\\\\", "\\").Replace("\\\"", "\""))).ToList();
    }
    public (List<SteamGame> Games, string Id, string Name) Read()
    {
        lock (gate)
        {
            try
            {
                using var steam = Registry.CurrentUser.OpenSubKey(@"Software\Valve\Steam");
                if (steam is null) return ([], "", "");
                if (DateTime.UtcNow >= nextScan)
                {
                    var root = steam.GetValue("SteamPath") as string;
                    var discovered = new Dictionary<string, SteamGame>();
                    if (!string.IsNullOrEmpty(root))
                    {
                        var folders = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { root };
                        foreach (var pair in ReadPairs(Path.Combine(root, "steamapps", "libraryfolders.vdf")))
                            if (pair.Key == "path") folders.Add(pair.Value);
                        foreach (var folder in folders.Take(32))
                        {
                            var apps = Path.Combine(folder, "steamapps");
                            if (!Directory.Exists(apps)) continue;
                            foreach (var manifest in Directory.EnumerateFiles(apps, "appmanifest_*.acf").Take(5000))
                            {
                                var pairs = ReadPairs(manifest).ToList();
                                var id = pairs.FirstOrDefault(p => p.Key == "appid").Value;
                                var name = pairs.FirstOrDefault(p => p.Key == "name").Value;
                                if (!string.IsNullOrEmpty(id) && id.All(char.IsAsciiDigit) && !string.IsNullOrEmpty(name)) discovered[id] = new(id, name);
                            }
                        }
                    }
                    games = discovered.Values.OrderBy(g => g.Name).ToList(); nextScan = DateTime.UtcNow.AddMinutes(1);
                }
                // Steam's local registry is best effort, not a public, stable API. No account or Web API key is needed.
                using var registryApps = steam.OpenSubKey("Apps");
                var running = new List<string>();
                if (registryApps is not null)
                    foreach (var id in registryApps.GetSubKeyNames())
                    {
                        using var app = registryApps.OpenSubKey(id);
                        if (app?.GetValue("Running") is int value && value == 1) running.Add(id);
                    }
                // Avoid bouncing between profiles when multiple games are running.
                if (running.Count != 1) return (games.ToList(), "", "");
                var active = running[0];
                return (games.ToList(), active, games.FirstOrDefault(g => g.Id == active)?.Name ?? $"Steam game {active}");
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or System.Security.SecurityException)
            { return (games.ToList(), "", ""); }
        }
    }
}
