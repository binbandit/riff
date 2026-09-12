using System.Net;
using System.Text.Json;
using Riff.Core;
using Xunit;

namespace Riff.Tests;

public class PadSuggestionTests
{
    static string Response(string label = "Air horn", string icon = "speaker.wave.2", string color = "orange", string status = "completed") =>
        JsonSerializer.Serialize(new { status, output = new[] { new { type = "message", content = new[] { new { type = "output_text", text = JsonSerializer.Serialize(new { label, icon, color }) } } } } });

    [Fact]
    public void ContextUsesNamesAndNeverIncludesAppPathsOrUrlSecrets()
    {
        var input = new PadSuggestionRequest("macro", "", [new("sound", "clip-id"), new("app", "app-id"), new("url", "https://user:password@example.com/music?token=secret#private")], "Party");
        var context = PadSuggestions.Context(input, [new("clip-id", "Air horn", 1)], [new("app-id", "Spotify", @"C:\private\spotify.exe")]);
        Assert.Contains("Air horn", context); Assert.Contains("Spotify", context); Assert.Contains("example.com/music", context);
        foreach (var secret in new[] { "clip-id", "app-id", "private", "password", "secret", "token=" }) Assert.DoesNotContain(secret, context);
        Assert.Throws<ArgumentException>(() => PadSuggestions.Context(input with { Steps = [new("macro", "")] }, [], []));
        Assert.Throws<ArgumentException>(() => PadSuggestions.Context(new("sound", "missing", [], ""), [], []));
    }

    [Theory]
    [InlineData("back", "Go back")]
    [InlineData("stop", "Stop all")]
    public void NavigationActionsNeedNoValue(string kind, string expected) =>
        Assert.Contains(expected, PadSuggestions.Context(new(kind, "", [], ""), [], []));

    [Fact]
    public void SwitchContextIncludesBothSidesAndDecksUseNames()
    {
        var request = new PadSuggestionRequest("switch", "", [new("text", "Hello")], "", [new("text", "Goodbye")]);
        var context = PadSuggestions.Context(request, [], []);
        Assert.Contains("Hello", context); Assert.Contains("Goodbye", context);
        Assert.Contains("Second press", context);
        Assert.Throws<ArgumentException>(() => PadSuggestions.Context(request with { AlternateSteps = [] }, [], []));
        Assert.Contains("Flight deck", PadSuggestions.Context(new("deck", "id", [], ""), [], [], [new("id", "Flight deck", "folder", [])]));
    }

    [Theory]
    [InlineData("", "mic", "blue", "completed")]
    [InlineData("Test", "unknown", "blue", "completed")]
    [InlineData("Test", "mic", "unknown", "completed")]
    [InlineData("Test", "mic", "blue", "incomplete")]
    public void InvalidResultsAreRejected(string label, string icon, string color, string status) =>
        Assert.ThrowsAny<Exception>(() => PadSuggestions.Parse(Response(label, icon, color, status)));

    [Fact]
    public void RejectsRefusalsAndUtf16Overflow()
    {
        Assert.ThrowsAny<Exception>(() => PadSuggestions.Parse("""{"status":"completed","output":[{"type":"message","content":[{"type":"refusal","refusal":"No"}]}]}"""));
        Assert.ThrowsAny<Exception>(() => PadSuggestions.Parse(Response(string.Concat(Enumerable.Repeat("🔥", 21)))));
    }

    [Fact]
    public async Task SendsLunaStructuredRequestAndParsesAppearance()
    {
        using var handler = new Handler(HttpStatusCode.OK, Response());
        using var client = new HttpClient(handler);
        var result = await new PadSuggestions(client).Suggest("Play sound: Air horn", "test-key", CancellationToken.None);
        Assert.Equal(new("Air horn", "speaker.wave.2", "orange"), result);
        Assert.Equal("https://api.openai.com/v1/responses", handler.Url);
        Assert.Equal("Bearer test-key", handler.Authorization);
        using var request = JsonDocument.Parse(handler.Body!);
        var root = request.RootElement;
        Assert.Equal("gpt-5.6-luna", root.GetProperty("model").GetString());
        Assert.False(root.GetProperty("store").GetBoolean());
        Assert.Equal("none", root.GetProperty("reasoning").GetProperty("effort").GetString());
        var format = root.GetProperty("text").GetProperty("format");
        Assert.True(format.GetProperty("strict").GetBoolean());
        Assert.Equal("json_schema", format.GetProperty("type").GetString());
        Assert.Contains("speaker.wave.2", format.GetProperty("schema").GetProperty("properties").GetProperty("icon").GetProperty("enum").EnumerateArray().Select(i => i.GetString()));
    }

    [Fact]
    public async Task ErrorsDoNotExposeProviderBodiesAndCancellationIsPreserved()
    {
        using var handler = new Handler(HttpStatusCode.Unauthorized, "secret provider details");
        using var client = new HttpClient(handler);
        var service = new PadSuggestions(client);
        var error = await Assert.ThrowsAsync<PadSuggestionException>(() => service.Suggest("Sound", "test-key", CancellationToken.None));
        Assert.DoesNotContain("secret", error.Message);
        using var cancellation = new CancellationTokenSource(); cancellation.Cancel();
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => service.Suggest("Sound", "test-key", cancellation.Token));
    }

    sealed class Handler(HttpStatusCode status, string body) : HttpMessageHandler
    {
        public string? Url, Authorization, Body;
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            Url = request.RequestUri?.ToString(); Authorization = request.Headers.Authorization?.ToString();
            Body = await request.Content!.ReadAsStringAsync(cancellationToken);
            return new(status) { Content = new StringContent(body) };
        }
    }
}
