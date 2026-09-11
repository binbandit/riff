using System.Net;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;

namespace Riff.Core;

public sealed partial record CompanionVersion(string Value, Version Number, string Prerelease) : IComparable<CompanionVersion>
{
    [GeneratedRegex(@"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?(?:\+([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$", RegexOptions.CultureInvariant)]
    private static partial Regex Pattern();
    public static CompanionVersion? Parse(string? text)
    {
        if (text is null || text.Length > 128) return null;
        var raw = text.StartsWith('v') ? text[1..] : text;
        var match = Pattern().Match(raw);
        if (!match.Success || !Version.TryParse($"{match.Groups[1]}.{match.Groups[2]}.{match.Groups[3]}", out var number)) return null;
        var pre = match.Groups[4].Value;
        if (pre.Split('.').Any(p => p.Length > 1 && p[0] == '0' && p.All(char.IsAsciiDigit))) return null;
        return new(raw, number, pre);
    }
    public int CompareTo(CompanionVersion? other)
    {
        if (other is null) return 1;
        var numeric = Number.CompareTo(other.Number);
        if (numeric != 0) return numeric;
        if (Prerelease == other.Prerelease) return 0;
        if (Prerelease.Length == 0) return 1;
        if (other.Prerelease.Length == 0) return -1;
        var left = Prerelease.Split('.'); var right = other.Prerelease.Split('.');
        for (var i = 0; i < Math.Min(left.Length, right.Length); i++)
        {
            var a = left[i]; var b = right[i];
            if (a == b) continue;
            var an = a.All(char.IsAsciiDigit); var bn = b.All(char.IsAsciiDigit);
            if (an != bn) return an ? -1 : 1;
            if (an && a.Length != b.Length) return a.Length.CompareTo(b.Length);
            return string.CompareOrdinal(a, b);
        }
        return left.Length.CompareTo(right.Length);
    }
}

public sealed record ReleaseAsset(long Id, string Name, string State, long Size);
public sealed record CompanionRelease(
    [property: JsonPropertyName("tag_name")] string Tag,
    bool Draft, bool Prerelease, List<ReleaseAsset> Assets)
{
    public CompanionVersion? Version => CompanionVersion.Parse(Tag.StartsWith("companion-", StringComparison.Ordinal) ? Tag[10..] : Tag);
    public bool IsStable => !Draft && !Prerelease && Version is { Prerelease.Length: 0 };
    public bool HasWindowsDownload => Version is { } version && Assets.Any(a => a.State == "uploaded" && a.Size > 0 &&
        new[] { $"Riff-{version.Number}-win-x64.zip", $"Riff-{version.Number}-win-arm64.zip", "Riff-win-x64.zip", "Riff-win-arm64.zip" }.Contains(a.Name));
    public ReleaseAsset? Changelog => Assets.FirstOrDefault(a => a.Name.Equals("CHANGELOG.md", StringComparison.OrdinalIgnoreCase) && a.State == "uploaded" && a.Id > 0 && a.Size > 0);
    public static Uri ReleasesPage { get; } = new("https://github.com/binbandit/riff/releases");
    public Uri Page => IsStable && HasWindowsDownload ? new(ReleasesPage + "/tag/" + Uri.EscapeDataString(Tag)) : ReleasesPage;
}

public sealed class CompanionReleaseClient(HttpClient client)
{
    static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);
    const string Api = "https://api.github.com/repos/binbandit/riff/releases";
    public static CompanionRelease? Latest(IEnumerable<CompanionRelease> releases)
    {
        var latest = releases.Where(r => r.IsStable && (r.Tag.StartsWith("companion-v", StringComparison.Ordinal) || r.HasWindowsDownload))
            .OrderByDescending(r => r.Version).FirstOrDefault();
        if (latest is not null && !latest.HasWindowsDownload) throw new InvalidDataException("The newest release's Windows downloads are not ready yet. Check again shortly.");
        return latest;
    }
    public async Task<CompanionRelease?> Fetch(CancellationToken cancellation = default)
    {
        var releases = new List<CompanionRelease>();
        for (var page = 1; page <= 10; page++)
        {
            var data = await Read(new($"{Api}?per_page=100&page={page}"), "application/vnd.github+json", 2 * 1024 * 1024, cancellation);
            var batch = JsonSerializer.Deserialize<List<CompanionRelease>>(data, Json) ?? throw new InvalidDataException("GitHub returned an unreadable release list.");
            if (batch.Any(r => r is null || r.Tag is null || r.Assets is null || r.Assets.Any(a => a is null || a.Name is null || a.State is null))) throw new InvalidDataException("GitHub returned an incomplete release list.");
            releases.AddRange(batch);
            if (batch.Count < 100) return Latest(releases);
        }
        throw new InvalidDataException("The release history is too large to check completely. Open GitHub to see the latest version.");
    }
    public async Task<string> FetchChangelog(CompanionRelease release, CancellationToken cancellation = default)
    {
        if (!release.IsStable || !release.HasWindowsDownload || release.Changelog is not { } asset) throw new InvalidDataException("This release does not include a CHANGELOG.md yet. You can read its release notes on GitHub.");
        if (asset.Size > 1024 * 1024) throw new InvalidDataException("This changelog is too large to display. Open the release on GitHub.");
        var data = await Read(new($"{Api}/assets/{asset.Id}"), "application/octet-stream", 1024 * 1024, cancellation);
        var markdown = new UTF8Encoding(false, true).GetString(data);
        if (string.IsNullOrWhiteSpace(markdown)) throw new InvalidDataException("The release changelog is empty.");
        return markdown.TrimStart('\uFEFF');
    }
    async Task<byte[]> Read(Uri url, string accept, int limit, CancellationToken cancellation)
    {
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellation);
        timeout.CancelAfter(TimeSpan.FromSeconds(15));
        using var request = new HttpRequestMessage(HttpMethod.Get, url);
        request.Headers.UserAgent.ParseAdd("Riff-Companion");
        request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue(accept));
        request.Headers.Add("X-GitHub-Api-Version", "2026-03-10");
        using var response = await client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, timeout.Token);
        if (response.StatusCode is HttpStatusCode.Forbidden or HttpStatusCode.TooManyRequests) throw new HttpRequestException("GitHub is limiting update checks. Try again later.");
        if (!response.IsSuccessStatusCode) throw new HttpRequestException("GitHub could not load the release. Check your connection and try again.");
        if (response.Content.Headers.ContentLength > limit) throw new InvalidDataException("GitHub's response is too large to display.");
        await using var source = await response.Content.ReadAsStreamAsync(timeout.Token);
        using var result = new MemoryStream();
        var buffer = new byte[16384];
        int count;
        while ((count = await source.ReadAsync(buffer, timeout.Token)) > 0)
        {
            if (result.Length + count > limit) throw new InvalidDataException("GitHub's response is too large to display.");
            result.Write(buffer, 0, count);
        }
        return result.ToArray();
    }
}
