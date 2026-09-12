using System.Net;
using System.Text.Json;
using Riff.Core;
using Xunit;

namespace Riff.Tests;

public class SoundSuggestionTests
{
    static SoundButtonSuggestion Button(string id) => new(id, "Air Horn", "speaker.wave.2", "orange");
    static string Response(params SoundButtonSuggestion[] buttons) => JsonSerializer.Serialize(new
    {
        status = "completed", output = new[] { new { type = "message", content = new[] {
            new { type = "output_text", text = JsonSerializer.Serialize(new SoundSuggestionBatch(buttons.ToList()), Wire.Json) }
        } } }
    });

    [Fact]
    public void ContextIncludesEverySelectedSoundAndDeckContext()
    {
        var request = new SoundSuggestionRequest(["horn", "win"], "Game night", "730", "app");
        var result = SoundSuggestions.Context(request, [new("horn", "Air horn", 1), new("win", "Victory", 2)], "Counter-Strike 2", "Discord");
        foreach (var value in new[] { "Air horn", "Victory", "Game night", "Counter-Strike 2", "Discord" }) Assert.Contains(value, result);
        Assert.Throws<ArgumentException>(() => SoundSuggestions.Context(request with { ClipIds = ["horn", "horn"] }, [], "", ""));
        Assert.Throws<ArgumentException>(() => SoundSuggestions.Context(request with { ClipIds = [] }, [], "", ""));
        Assert.Throws<ArgumentException>(() => SoundSuggestions.Context(request with { ClipIds = ["missing"] }, [], "", ""));
        Assert.Throws<ArgumentException>(() => SoundSuggestions.Context(request with { ClipIds = Enumerable.Range(0, 49).Select(i => i.ToString()).ToList() }, [], "", ""));
    }

    [Fact]
    public void ResultsAreMappedByIdentityAndReturnedInSelectionOrder()
    {
        var result = SoundSuggestions.Parse(Response(Button("win") with { Label = " Victory " }, Button("horn")), ["horn", "win"]);
        Assert.Equal(new[] { "horn", "win" }, result.Buttons.Select(b => b.ClipId));
        Assert.Equal("Victory", result.Buttons[1].Label);
        Assert.ThrowsAny<Exception>(() => SoundSuggestions.Parse(Response(Button("horn")), ["horn", "win"]));
        Assert.ThrowsAny<Exception>(() => SoundSuggestions.Parse(Response(Button("horn"), Button("horn")), ["horn", "win"]));
        Assert.ThrowsAny<Exception>(() => SoundSuggestions.Parse(Response(Button("horn"), Button("other")), ["horn", "win"]));
        Assert.ThrowsAny<Exception>(() => SoundSuggestions.Parse(Response(Button("horn") with { Icon = "missing" }), ["horn"]));
        Assert.ThrowsAny<Exception>(() => SoundSuggestions.Parse(Response(Button("horn") with { Color = "missing" }), ["horn"]));
        Assert.ThrowsAny<Exception>(() => SoundSuggestions.Parse(Response(Button("horn") with { Label = new string('x', 41) }), ["horn"]));
    }

    [Fact]
    public async Task FullDeckUsesOneLunaRequestWithAllSoundIdentities()
    {
        var ids = Enumerable.Range(0, 48).Select(i => $"sound-{i}").ToList();
        using var handler = new Handler(Response(ids.Select(Button).Reverse().ToArray()));
        using var client = new HttpClient(handler);
        var result = await new SoundSuggestions(client).Suggest("selected sounds", ids, "test-key", CancellationToken.None);
        Assert.Equal(1, handler.Calls);
        Assert.Equal(ids, result.Buttons.Select(b => b.ClipId));
        using var json = JsonDocument.Parse(handler.Body!);
        var root = json.RootElement;
        Assert.Equal("gpt-5.6-luna", root.GetProperty("model").GetString());
        Assert.False(root.GetProperty("store").GetBoolean());
        var format = root.GetProperty("text").GetProperty("format");
        Assert.True(format.GetProperty("strict").GetBoolean());
        var schema = format.GetProperty("schema").GetProperty("properties").GetProperty("buttons");
        Assert.Equal(48, schema.GetProperty("minItems").GetInt32());
        Assert.Equal(ids, schema.GetProperty("items").GetProperty("properties").GetProperty("clipId").GetProperty("enum").EnumerateArray().Select(i => i.GetString()));
    }

    sealed class Handler(string body) : HttpMessageHandler
    {
        public string? Body;
        public int Calls;
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            Calls++;
            Body = await request.Content!.ReadAsStringAsync(cancellationToken);
            return new(HttpStatusCode.OK) { Content = new StringContent(body) };
        }
    }
}
