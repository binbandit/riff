using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Hosting;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using System.Collections.Concurrent;
using System.Text.Json;
using System.Threading.RateLimiting;
using Riff.Core;

namespace Riff.Companion;

public sealed class CompanionServer(StateStore store, PairingIdentity identity, AudioEngine audio, ActionRunner runner)
{
    WebApplication? app;
    readonly SteamPresence steam = new();
    readonly ConcurrentDictionary<string, DateTime> received = new();
    readonly SemaphoreSlim importGate = new(1, 1);
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
                presence.Games, presence.Id, presence.Name);
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
            await runner.Run(pad); Activity?.Invoke($"Played action: {pad.Title}"); return new { ok = true };
        });
        app.MapPost("/api/stop", () => { runner.Stop(); Activity?.Invoke("All sounds and sequences stopped"); return new { ok = true }; });
        app.MapPost("/api/preview", async (PreviewRequest preview) =>
        {
            await runner.Run(new("preview", "Preview", "waveform", "orange", "sound", preview.ClipId, []));
            return new { ok = true };
        });
        app.MapPut("/api/audio", (AudioSettings settings) =>
        {
            if (!float.IsFinite(settings.Volume) || settings.Volume is < 0 or > 1) throw new ArgumentException("Volume must be between 0 and 100%.");
            if (!audio.Devices().Any(d => d.Id == settings.OutputId)) throw new ArgumentException("This audio output is disconnected. Choose another output.");
            lock (store.Gate) store.Save(store.State with { OutputId = settings.OutputId, Volume = settings.Volume, Version = store.State.Version + 1 });
            audio.SetVolume(settings.Volume); return Snapshot();
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
            finally { if (temporary is not null) File.Delete(temporary); importGate.Release(); }
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
                if (store.State.Decks.SelectMany(d => d.Pads).Any(p => p.Kind == "sound" && p.Value == id || p.Steps.Any(s => s.Kind == "sound" && s.Value == id)))
                    throw new ArgumentException("Remove buttons using this sound before deleting it.");
                store.Save(store.State with { Clips = store.State.Clips.Where(c => c.Id != clip.Id).ToList(), Version = store.State.Version + 1 });
                try { File.Delete(store.ClipPath(clip.Id)); } catch (IOException) { /* A playing clip can be cleaned up after playback. */ }
                return Snapshot();
            }
        });
        await app.StartAsync();
    }
    public async Task Stop() { runner.Stop(); if (app is not null) { await app.StopAsync(); await app.DisposeAsync(); } }
    public record PreviewRequest(string ClipId);
}
