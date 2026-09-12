using System.Security.Cryptography;
using System.Text.Json;

namespace Riff.Core;

public record PackSound(string Id, string Name, string FileName, string SourceURL, string Provider,
    string Uploader, string Rights, int ByteCount, string Sha256, double Duration)
{
    public string? OriginalDownloadURL { get; init; }
    public string? Acquisition { get; init; }
    public string ClipId => "pack-" + Id;
    public void Validate(ReadOnlySpan<byte> bytes)
    {
        if (bytes.Length != ByteCount || !Convert.ToHexString(SHA256.HashData(bytes)).Equals(Sha256, StringComparison.OrdinalIgnoreCase))
            throw new ArgumentException($"The audio for {Name} changed or is incomplete. Update Riff and try again.");
    }
}
public record SoundPack(string Id, string Name, string Description, string Icon, string Color, List<PackSound> Sounds);

public static class SoundPacks
{
    public static readonly IReadOnlyList<SoundPack> Catalog = Load();
    static List<SoundPack> Load()
    {
        using var stream = typeof(SoundPacks).Assembly.GetManifestResourceStream("Riff.SoundPacks.json")
            ?? throw new InvalidDataException("The sound pack catalog is missing.");
        return JsonSerializer.Deserialize<List<SoundPack>>(stream, Wire.Json)
            ?? throw new InvalidDataException("The sound pack catalog is invalid.");
    }
    // Remember catalog entries already offered, so deleted sounds stay deleted across updates.
    public static SavedState Populate(SavedState state)
    {
        var known = (state.KnownBundledSoundIds ?? []).ToHashSet();
        var existing = state.Clips.Select(c => c.Id).ToHashSet();
        var additions = Catalog.SelectMany(p => p.Sounds)
            .Where(s => !known.Contains(s.ClipId) && !existing.Contains(s.ClipId))
            .Select(s => new Clip(s.ClipId, s.Name, s.Duration)).ToList();
        known.UnionWith(Catalog.SelectMany(p => p.Sounds).Select(s => s.ClipId));
        if (additions.Count == 0 && known.SetEquals(state.KnownBundledSoundIds ?? [])) return state;
        return state with { Clips = [.. state.Clips, .. additions], KnownBundledSoundIds = known.Order().ToList(), Version = state.Version + 1 };
    }

    public static PackSound Find(string packId, string soundId) =>
        Catalog.FirstOrDefault(p => p.Id == packId)?.Sounds.FirstOrDefault(s => s.Id == soundId)
        ?? throw new ArgumentException("This sound pack is unavailable. Update both Riff apps and try again.");
}
