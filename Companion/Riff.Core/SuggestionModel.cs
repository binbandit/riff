using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;

namespace Riff.Core;

public static class SuggestionModel
{
    public static async Task<string> Generate<TSchema>(HttpClient client, string apiKey, string context, string instructions,
        string name, TSchema schema, int maxTokens, CancellationToken cancellationToken)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, "https://api.openai.com/v1/responses");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", apiKey);
        request.Content = JsonContent.Create(new
        {
            model = PadSuggestions.Model, store = false, reasoning = new { effort = "none" }, max_output_tokens = maxTokens,
            instructions, input = context,
            text = new { format = new { type = "json_schema", name, strict = true, schema } }
        });
        using var response = await client.SendAsync(request, cancellationToken);
        if (!response.IsSuccessStatusCode)
            throw new PadSuggestionException(response.StatusCode switch
            {
                System.Net.HttpStatusCode.Unauthorized or System.Net.HttpStatusCode.Forbidden => "Check your OpenAI API key and model access in the Windows companion.",
                System.Net.HttpStatusCode.TooManyRequests => "AI suggestions are busy or your OpenAI credit limit was reached. Try again later.",
                _ => "AI suggestions are unavailable right now. You can still save without them."
            });
        return await response.Content.ReadAsStringAsync(cancellationToken);
    }

    public static string OutputText(string data)
    {
        using var document = JsonDocument.Parse(data);
        var root = document.RootElement;
        if (root.GetProperty("status").GetString() != "completed") throw new JsonException("Incomplete suggestion.");
        return root.GetProperty("output").EnumerateArray()
            .Where(item => item.GetProperty("type").GetString() == "message")
            .SelectMany(item => item.GetProperty("content").EnumerateArray())
            .Where(item => item.GetProperty("type").GetString() == "output_text")
            .Select(item => item.GetProperty("text").GetString()).FirstOrDefault() ?? throw new JsonException("No suggestion returned.");
    }
}
