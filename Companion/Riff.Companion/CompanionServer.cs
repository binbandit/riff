using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Hosting;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using System.Collections.Concurrent;
using System.Text.Json;
using System.Threading.RateLimiting;
using Microsoft.AspNetCore.RateLimiting;
using Riff.Core;

namespace Riff.Companion;

public sealed class CompanionServer(StateStore store, PairingIdentity identity, AudioEngine audio, ActionRunner runner)
{
    WebApplication? app;
    readonly SteamPresence steam = new();
    readonly ConcurrentDictionary<string, DateTime> received = new();
    readonly SemaphoreSlim importGate = new(1, 1);
    public AISettings AI { get; } = new(store.Folder);
    static readonly HttpClient suggestionClient = new(new HttpClientHandler { AllowAutoRedirect = false }) { Timeout = TimeSpan.FromSeconds(25), MaxResponseContentBufferSize = 64 * 1024 };
    readonly PadSuggestions suggestions = new(suggestionClient);
    readonly DeckSuggestions deckSuggestions = new(suggestionClient);
    readonly SoundSuggestions soundSuggestions = new(suggestionClient);
    public event Action<string>? Activity;
    public DateTime LastSeen { get; private set; }
    public Snapshot Snapshot()
    {
        var presence = steam.Read();
        lock (store.Gate)
        {
            var s = store.State;
            return new(s.Version, s.Decks, s.Clips, audio.Devices(), s.OutputId, s.Volume,
                s.Apps.Select(a => new LaunchTargetInfo(a.Id, a.Name)).ToList(), Environment.MachineName,
                presence.Games, presence.Id, presence.Name, ["audio-monitor-v1", "soundboard-playback-v1", "soundboard-queue-v1", "bundled-sounds-v1", "soundboard-only-v1", "deck-actions-v1", "pinned-pads-v1", "key-logic-v1", "smart-profiles-v1", "clip-audio-v1", "pad-suggestions-v1", "deck-suggestions-v1", "sound-suggestions-v1", .. AI.Enabled ? new[] { "pad-suggestions-enabled-v1" } : Array.Empty<string>()], CompanionBuild.Version, s.SoundboardOnly, AppPresence.Read(s.Apps), runner.SwitchStatus(), s.MonitorEnabled, s.MonitorOutputId, s.MonitorVolume);
        }
    }
    public async Task Start()
    {
        var builder = WebApplication.CreateSlimBuilder();
        builder.Logging.ClearProviders();
        builder.WebHost.ConfigureKestrel(options =>
        {
            options.Limits.MaxRequestBodySize = 20 * 1024 * 1024;
            options.Limits.RequestHeadersTimeout = TimeSpan.FromSeconds(10);
            options.ListenAnyIP(PairingIdentity.Port, endpoint => endpoint.UseHttps(identity.Certificate));
        });
        builder.Services.ConfigureHttpJsonOptions(options => options.SerializerOptions.UnmappedMemberHandling = System.Text.Json.Serialization.JsonUnmappedMemberHandling.Disallow);
        builder.Services.AddRateLimiter(options =>
        {
            options.RejectionStatusCode = 429;
            options.AddFixedWindowLimiter("suggestions", limiter =>
            {
                limiter.PermitLimit = 30; limiter.Window = TimeSpan.FromMinutes(1); limiter.QueueLimit = 0;
            });
            options.GlobalLimiter = PartitionedRateLimiter.Create<HttpContext, string>(context =>
                RateLimitPartition.GetFixedWindowLimiter(context.Connection.RemoteIpAddress?.ToString() ?? "unknown",
                    _ => new FixedWindowRateLimiterOptions { PermitLimit = 100, Window = TimeSpan.FromSeconds(1), QueueLimit = 0 }));
        });
        app = builder.Build();
        app.Use(async (context, next) =>
        {
            try { await next(); }
            catch (Exception ex)
            {
                context.Response.StatusCode = ex switch
                {
                    StateConflictException => 409,
                    ArgumentException or JsonException or BadHttpRequestException => 400,
                    OperationCanceledException => 409,
                    _ => 500
                };
                var message = ex is OperationCanceledException ? "The sequence was stopped." : ex is ArgumentException or StateConflictException or BadHttpRequestException ? ex.Message : "The PC could not complete this action. Check the companion's activity log and audio output.";
                Activity?.Invoke(ex.Message);
                await context.Response.WriteAsJsonAsync(new { error = message });
            }
        });
        app.UseRateLimiter();
        app.Use(async (context, next) =>
        {
            if (!identity.Authorize(context.Request.Headers.Authorization.ToString()))
            { context.Response.StatusCode = 401; await context.Response.WriteAsJsonAsync(new { error = "Pairing expired. Copy a new pairing link from your PC." }); return; }
            LastSeen = DateTime.UtcNow;
            await next();
        });
        app.MapGet("/api/state", () => Snapshot());
        app.MapPost("/api/deck-suggestion", async (DeckSuggestionRequest request, HttpContext context) =>
        {
            var key = AI.ApiKey;
            if (string.IsNullOrEmpty(key)) return Results.Json(new { error = "Set up AI suggestions in the Windows companion's Controls tab." }, statusCode: 503);
            List<DeckSuggestionOption> options;
            string input;
            var games = steam.Read().Games;
            lock (store.Gate)
            {
                options = DeckSuggestions.Options(store.State);
                input = DeckSuggestions.Context(request, games, store.State.Apps, options);
            }
            try { return Results.Ok(await deckSuggestions.Suggest(input, options, key, context.RequestAborted)); }
            catch (PadSuggestionException ex) { return Results.Json(new { error = ex.Message }, statusCode: 502); }
            catch (Exception ex) when (ex is HttpRequestException || ex is OperationCanceledException && !context.RequestAborted.IsCancellationRequested)
            { return Results.Json(new { error = "AI suggestions could not connect. Try again or create an empty deck." }, statusCode: 503); }
        }).RequireRateLimiting("suggestions");
        app.MapPost("/api/sound-suggestions", async (SoundSuggestionRequest request, HttpContext context) =>
        {
            var key = AI.ApiKey;
            if (string.IsNullOrEmpty(key)) return Results.Json(new { error = "Set up AI suggestions in the Windows companion's Controls tab." }, statusCode: 503);
            string input;
            var gameName = steam.Read().Games.FirstOrDefault(g => g.Id == request.GameId)?.Name ?? "";
            lock (store.Gate)
                input = SoundSuggestions.Context(request, store.State.Clips, gameName, store.State.Apps.FirstOrDefault(a => a.Id == request.AppId)?.Name ?? "");
            try { return Results.Ok(await soundSuggestions.Suggest(input, request.ClipIds, key, context.RequestAborted)); }
            catch (PadSuggestionException ex) { return Results.Json(new { error = ex.Message }, statusCode: 502); }
            catch (Exception ex) when (ex is HttpRequestException || ex is OperationCanceledException && !context.RequestAborted.IsCancellationRequested)
            { return Results.Json(new { error = "AI suggestions could not connect. Try again or use the current buttons." }, statusCode: 503); }
        }).RequireRateLimiting("suggestions");
        app.MapPost("/api/pad-suggestion", async (PadSuggestionRequest request, HttpContext context) =>
        {
            var key = AI.ApiKey;
            if (string.IsNullOrEmpty(key)) return Results.Json(new { error = "Set up AI suggestions in the Windows companion's Controls tab." }, statusCode: 503);
            string input;
            lock (store.Gate) input = PadSuggestions.Context(request, store.State.Clips, store.State.Apps, store.State.Decks);
            try { return Results.Ok(await suggestions.Suggest(input, key, context.RequestAborted)); }
            catch (PadSuggestionException ex) { return Results.Json(new { error = ex.Message }, statusCode: 502); }
            catch (Exception ex) when (ex is HttpRequestException || ex is OperationCanceledException && !context.RequestAborted.IsCancellationRequested)
            { return Results.Json(new { error = "AI suggestions could not connect. Try again or choose your own appearance." }, statusCode: 503); }
        }).RequireRateLimiting("suggestions");
        app.MapGet("/api/playback", () => audio.Status());
        app.MapGet("/api/clips/{id}/audio", (string id) =>
        {
            lock (store.Gate)
            {
                if (!store.State.Clips.Any(c => c.Id == id)) throw new ArgumentException("Sound not found.");
                var path = store.ClipPath(id);
                return Results.Stream(File.OpenRead(path), Path.GetExtension(path) == ".mp3" ? "audio/mpeg" : "audio/wav");
            }
        });
        app.MapPut("/api/decks", (DeckUpdate update) => { store.UpdateDecks(update); Activity?.Invoke("Deck layout saved"); return Snapshot(); });
        app.MapPost("/api/trigger", async (Trigger trigger) =>
        {
            if (!Guid.TryParse(trigger.RequestId, out _)) throw new ArgumentException("Invalid action request ID.");
            foreach (var entry in received.Where(e => e.Value < DateTime.UtcNow.AddMinutes(-5))) received.TryRemove(entry.Key, out _);
            if (received.Count > 10000) throw new ArgumentException("Too many recent actions. Wait a moment.");
            Pad? pad;
            lock (store.Gate) pad = store.State.Decks.SelectMany(d => d.Pads).FirstOrDefault(p => p.Id == trigger.PadId);
            if (pad is null) throw new ArgumentException("This button no longer exists. Refresh your decks.");
            if (!received.TryAdd(trigger.RequestId, DateTime.UtcNow)) throw new ArgumentException("This action was already received; it will not run again.");
            await runner.Run(pad, trigger.Toggle, trigger.SoundMode, trigger.Gesture); Activity?.Invoke($"Sound/action: {pad.Title}"); return new { ok = true, playback = audio.Status(), switchState = runner.SwitchStatus() };
        });
        app.MapPost("/api/stop", () => { runner.Stop(); Activity?.Invoke("All sounds and sequences stopped"); return new { ok = true, playback = audio.Status() }; });
        app.MapPost("/api/preview", async (PreviewRequest preview) =>
        {
            await runner.Run(new("preview", "Preview", "waveform", "orange", "sound", preview.ClipId, []), soundMode: preview.SoundMode);
            return new { ok = true, playback = audio.Status() };
        });
        app.MapPut("/api/audio", (AudioSettings settings) =>
        {
            var devices = audio.Devices();
            lock (store.Gate)
            {
                store.Save(AudioRouting.Apply(store.State, settings, devices));
                audio.SetVolume(store.State.Volume);
                audio.SetMonitorVolume(store.State.MonitorVolume);
            }
            return Snapshot();
        });
        app.MapPost("/api/clips", async (HttpRequest request) =>
        {
            if (!await importGate.WaitAsync(0)) throw new ArgumentException("Another sound is importing. Try again shortly.");
            string? temporary = null;
            try
            {
                var ext = request.Query["ext"].ToString().ToLowerInvariant();
                if (ext is not ("wav" or "mp3" or "m4a" or "aac" or "aiff" or "aif")) throw new ArgumentException("Import WAV, MP3, M4A, AAC or AIFF audio.");
                var name = request.Query["name"].ToString(); Rules.CheckText(name, 60, "Sound name");
                temporary = Path.Combine(store.Folder, Guid.NewGuid().ToString("N") + "." + ext);
                await using (var file = File.Create(temporary))
                    await request.Body.CopyToAsync(file, request.HttpContext.RequestAborted);
                var clip = AudioEngine.Import(temporary, name, store);
                Activity?.Invoke($"Imported sound: {clip.Name}"); return clip;
            }
            finally { try { DeleteTemporaryUpload(temporary); } finally { importGate.Release(); } }
        });
        app.MapPut("/api/clips/{id}", (string id, ClipRename rename) =>
        {
            store.RenameClip(id, rename);
            Activity?.Invoke("Sound renamed");
            return Snapshot();
        });
        app.MapDelete("/api/clips/{id}", (string id) =>
        {
            lock (store.Gate)
            {
                var clip = store.State.Clips.FirstOrDefault(c => c.Id == id) ?? throw new ArgumentException("Sound not found.");
                if (store.State.Decks.SelectMany(d => d.Pads).Any(p => p.Uses("sound", id)))
                    throw new ArgumentException("Remove buttons using this sound before deleting it.");
                store.Save(store.State with { Clips = store.State.Clips.Where(c => c.Id != clip.Id).ToList(), Version = store.State.Version + 1 });
                try { File.Delete(store.ClipPath(clip.Id)); } catch (IOException) { /* A playing clip can be cleaned up after playback. */ }
                return Snapshot();
            }
        });
        await app.StartAsync();
    }
    static void DeleteTemporaryUpload(string? path)
    {
        if (path is null) return;
        try { File.Delete(path); }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            // A scanner can hold a completed upload briefly. Do not turn a saved clip into a failed import.
            System.Diagnostics.Trace.TraceWarning("Could not remove a temporary sound upload: {0}", error.Message);
        }
    }
    public async Task Stop()
    {
        try { runner.Stop(); }
        finally
        {
            var running = Interlocked.Exchange(ref app, null);
            if (running is not null)
            {
                try { await running.StopAsync(); }
                finally { await running.DisposeAsync(); }
            }
        }
    }
    public record PreviewRequest(string ClipId, string? SoundMode = null);
}
