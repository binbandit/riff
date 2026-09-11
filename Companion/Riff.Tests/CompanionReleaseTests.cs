using System.Net;
using System.Text;
using System.Text.Json;
using Riff.Core;
using Xunit;

namespace Riff.Tests;

public class CompanionReleaseTests
{
    static CompanionRelease Release(string tag = "companion-v1.2.3", bool draft = false, bool prerelease = false, params ReleaseAsset[] assets) =>
        new(tag, draft, prerelease, assets.Length == 0 ? [new(1, "Riff-1.2.3-win-x64.zip", "uploaded", 100), new(2, "CHANGELOG.md", "uploaded", 30)] : assets.ToList());

    [Theory]
    [InlineData("0.0.0-dev", "0.0.0")]
    [InlineData("1.2.3-alpha.2", "1.2.3-alpha.10")]
    [InlineData("1.2.3-beta", "1.2.3")]
    [InlineData("1.2.9", "1.2.10")]
    [InlineData("1.9.0", "2.0.0")]
    public void VersionsUseSemanticOrdering(string old, string latest) => Assert.True(CompanionVersion.Parse(old)!.CompareTo(CompanionVersion.Parse(latest)) < 0);

    [Theory]
    [InlineData("1.2")]
    [InlineData("01.2.3")]
    [InlineData("1.2.3-01")]
    [InlineData("1.2.3+")]
    [InlineData("../../1.2.3")]
    public void InvalidVersionsAreRejected(string input) => Assert.Null(CompanionVersion.Parse(input));

    [Fact]
    public void HighestStableWindowsReleaseWinsAndPendingNewReleaseIsExplicit()
    {
        var expected = Release();
        Assert.Equal(expected, CompanionReleaseClient.Latest([Release("ipad-v9.0.0"), Release("companion-v2.0.0", draft: true), Release("companion-v3.0.0", prerelease: true), expected]));
        var pending = Release("companion-v2.0.0", assets: [new(1, "CHANGELOG.md", "uploaded", 100)]);
        Assert.Throws<InvalidDataException>(() => CompanionReleaseClient.Latest([expected, pending]));
        Assert.Equal(new Uri("https://github.com/binbandit/riff/releases/tag/companion-v1.2.3"), expected.Page);
    }

    [Fact]
    public async Task PublicReleaseAndAssetRequestsUseNoPairingCredentialsAndPreserveMarkdown()
    {
        const string markdown = "# New\n\n- **Soundboard** mode\n\n<!-- generated -->\n";
        var calls = new List<HttpRequestMessage>();
        using var http = new HttpClient(new Handler(request =>
        {
            calls.Add(request);
            Assert.Null(request.Headers.Authorization);
            Assert.Equal("api.github.com", request.RequestUri!.Host);
            return request.RequestUri.AbsolutePath.EndsWith("/assets/2") ? Response(markdown) : Response(JsonSerializer.Serialize(new[] { Release() }, new JsonSerializerOptions(JsonSerializerDefaults.Web)));
        }));
        var client = new CompanionReleaseClient(http);
        var release = (await client.Fetch())!;
        Assert.Equal(markdown, await client.FetchChangelog(release));
        Assert.Equal("application/octet-stream", calls[1].Headers.Accept.Single().MediaType);
        Assert.Equal("Riff-Companion", calls[0].Headers.UserAgent.ToString());
    }

    [Fact]
    public async Task PaginatesBeforeSelectingLatest()
    {
        var count = 0;
        using var http = new HttpClient(new Handler(_ =>
        {
            count++;
            return Response(JsonSerializer.Serialize(count == 1 ? Enumerable.Repeat(Release("ipad-v1.2.3"), 100).ToArray() : [Release()], new JsonSerializerOptions(JsonSerializerDefaults.Web)));
        }));
        Assert.Equal("companion-v1.2.3", (await new CompanionReleaseClient(http).Fetch())!.Tag);
        Assert.Equal(2, count);
    }

    [Fact]
    public async Task MissingLargeInvalidAndRateLimitedChangelogsReportFailure()
    {
        using var http = new HttpClient(new Handler(_ => new HttpResponseMessage(HttpStatusCode.Forbidden)));
        var client = new CompanionReleaseClient(http);
        await Assert.ThrowsAsync<HttpRequestException>(() => client.Fetch());
        await Assert.ThrowsAsync<InvalidDataException>(() => client.FetchChangelog(Release(assets: [new(1, "Riff-1.2.3-win-x64.zip", "uploaded", 100)])));
        await Assert.ThrowsAsync<InvalidDataException>(() => client.FetchChangelog(Release(assets: [new(1, "Riff-1.2.3-win-x64.zip", "uploaded", 100), new(2, "CHANGELOG.md", "uploaded", 1024 * 1024 + 1)])));
        using var invalid = new HttpClient(new Handler(_ => new(HttpStatusCode.OK) { Content = new ByteArrayContent([0xFF]) }));
        await Assert.ThrowsAsync<DecoderFallbackException>(() => new CompanionReleaseClient(invalid).FetchChangelog(Release()));
        using var over = new HttpClient(new Handler(_ => Response(new string('x', 1024 * 1024 + 1))));
        await Assert.ThrowsAsync<InvalidDataException>(() => new CompanionReleaseClient(over).FetchChangelog(Release()));
    }

    [Fact]
    public void MarkdownUsesNativeStylesAndDoesNotRenderExecutableContent()
    {
        var rtf = ReleaseMarkdown.ToRtf("""
            <!-- hidden generated text -->
            # Fresh sounds
            A **bold** and *soft* ~~old~~ `clip`.
            - [x] Installed
            - Another
              - Nested
            > Keep playing
            [Read more](https://github.com/binbandit/riff)
            [Blocked](javascript:alert(1))
            ![No remote image](https://example.com/tracking.png)
            ```text
            {\\rtf1 hello}
            ```
            | Action | Result |
            | --- | --- |
            | Tap | Play |
            """, CompanionRelease.ReleasesPage);
        Assert.StartsWith("{\\rtf1", rtf);
        Assert.Contains("\\b\\fs38", rtf);
        Assert.Contains("{\\b bold}", rtf);
        Assert.Contains("{\\i soft}", rtf);
        Assert.Contains("{\\strike old}", rtf);
        Assert.Contains("\\li600", rtf);
        Assert.Contains("\\trowd", rtf);
        Assert.Contains("HYPERLINK", rtf);
        Assert.DoesNotContain("hidden generated", rtf);
        Assert.DoesNotContain("javascript:", rtf);
        Assert.DoesNotContain("tracking.png", rtf);
        Assert.Contains("\\{\\\\\\\\rtf1 hello\\}", rtf);
        Assert.Contains("No remote image", rtf);
        Assert.Null(ReleaseMarkdown.SafeLink(CompanionRelease.ReleasesPage, "file:///C:/Windows"));
    }
    [Fact]
    public void FriendlyRichEditLinksOpenTheirHiddenTargetAndRejectUnsafeTargets()
    {
        var expected = new Uri("https://github.com/binbandit/riff/releases");
        Assert.Equal(expected, ReleaseMarkdown.ClickedLink("HYPERLINK \"https://github.com/binbandit/riff/releases\"Read more"));
        Assert.Equal(expected, ReleaseMarkdown.ClickedLink(expected.AbsoluteUri));
        Assert.Null(ReleaseMarkdown.ClickedLink("HYPERLINK \"file:///C:/Windows\"Open"));
        Assert.Null(ReleaseMarkdown.ClickedLink("HYPERLINK \"javascript:alert(1)\"Open"));
        Assert.Null(ReleaseMarkdown.ClickedLink("HYPERLINK \"https://github.com"));
        Assert.Null(ReleaseMarkdown.ClickedLink("Read more"));
    }
    static HttpResponseMessage Response(string body) => new(HttpStatusCode.OK) { Content = new StringContent(body, Encoding.UTF8) };
    sealed class Handler(Func<HttpRequestMessage, HttpResponseMessage> respond) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken) => Task.FromResult(respond(request));
    }
}
