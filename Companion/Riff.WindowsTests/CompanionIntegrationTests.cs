using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Cryptography;
using Riff.Companion;
using Riff.Core;
using Xunit;

namespace Riff.WindowsTests;

public class CompanionIntegrationTests
{
    [Fact]
    public async Task RealHttpsServerRequiresPairingPersistsDecksAndRejectsStaleWrites()
    {
        var folder = Path.Combine(Path.GetTempPath(), "riff-test-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(folder);
        try
        {
            var store = new StateStore(folder);
            using var identity = new PairingIdentity(folder);
            using var audio = new AudioEngine();
            using var runner = new ActionRunner(store, audio);
            var server = new CompanionServer(store, identity, audio, runner);
            await server.Start();
            try
            {
                var fingerprint = SHA256.HashData(identity.Certificate.RawData);
                using var handler = new HttpClientHandler
                {
                    ServerCertificateCustomValidationCallback = (_, certificate, _, _) => certificate is not null && CryptographicOperations.FixedTimeEquals(SHA256.HashData(certificate.RawData), fingerprint)
                };
                using var client = new HttpClient(handler) { BaseAddress = new Uri($"https://localhost:{PairingIdentity.Port}") };
                Assert.Equal(HttpStatusCode.Unauthorized, (await client.GetAsync("/api/state")).StatusCode);
                Assert.Equal(HttpStatusCode.Unauthorized, (await client.GetAsync("/api/playback")).StatusCode);
                Assert.Equal(HttpStatusCode.Unauthorized, (await client.PutAsJsonAsync("/api/queue", new QueueUpdate("clear", "pc", 0), Wire.Json)).StatusCode);
                Assert.Equal(HttpStatusCode.Unauthorized, (await client.GetAsync("/api/clips/nope/audio")).StatusCode);
                Assert.Equal(HttpStatusCode.Unauthorized, (await client.PostAsJsonAsync("/api/sound-suggestions", new SoundSuggestionRequest(["nope"], "Game night"), Wire.Json)).StatusCode);
                client.DefaultRequestHeaders.Add("X-Riff-Theme", "ocean");
                client.DefaultRequestHeaders.Add("X-Riff-Appearance", "dark");
                Assert.Equal(HttpStatusCode.Unauthorized, (await client.GetAsync("/api/state")).StatusCode);
                var appearancePath = Path.Combine(folder, "appearance.json");
                Assert.False(File.Exists(appearancePath));
                client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", identity.Token);
                var snapshot = (await client.GetFromJsonAsync<Snapshot>("/api/state", Wire.Json))!;
                Assert.Equal(new CompanionAppearance("ocean", true),
                    System.Text.Json.JsonSerializer.Deserialize<CompanionAppearance>(await File.ReadAllTextAsync(appearancePath)));
                client.DefaultRequestHeaders.Remove("X-Riff-Theme");
                client.DefaultRequestHeaders.Add("X-Riff-Theme", "future-theme");
                (await client.GetAsync("/api/state")).EnsureSuccessStatusCode();
                Assert.Equal(new CompanionAppearance("ocean", true),
                    System.Text.Json.JsonSerializer.Deserialize<CompanionAppearance>(await File.ReadAllTextAsync(appearancePath)));
                client.DefaultRequestHeaders.Remove("X-Riff-Theme");
                client.DefaultRequestHeaders.Remove("X-Riff-Appearance");
                Assert.Equal(2, snapshot.Decks.Count);
                Assert.True(snapshot.SoundboardOnly);
                Assert.Contains("soundboard-only-v1", snapshot.Capabilities!);
                Assert.Contains("deck-actions-v1", snapshot.Capabilities!);
                Assert.Contains("pinned-pads-v1", snapshot.Capabilities!);
                Assert.Contains("smart-profiles-v1", snapshot.Capabilities!);
                Assert.Contains("sound-suggestions-v1", snapshot.Capabilities!);
                Assert.Equal(HttpStatusCode.ServiceUnavailable, (await client.PostAsJsonAsync("/api/sound-suggestions", new SoundSuggestionRequest(["nope"], "Game night"), Wire.Json)).StatusCode);
                Assert.NotNull(snapshot.SwitchState);
                Assert.Empty(snapshot.SwitchState.PadIds);
                Assert.NotNull(snapshot.ActiveAppId);
                foreach (var pad in snapshot.Decks.SelectMany(d => d.Pads).Where(p => p.Kind != "sound"))
                {
                    var blocked = await client.PostAsJsonAsync("/api/trigger", new Trigger(pad.Id, Guid.NewGuid().ToString()), Wire.Json);
                    Assert.Equal(HttpStatusCode.BadRequest, blocked.StatusCode);
                    Assert.Contains("Soundboard mode is on", await blocked.Content.ReadAsStringAsync());
                }
                // A delayed automation must not execute after mode is re-enabled, even if enabled again.
                runner.SetSoundboardOnly(false);
                Assert.False(server.Snapshot().SoundboardOnly);
                Assert.False(new StateStore(folder).State.SoundboardOnly);
                var pending = runner.Run(new("cancel-check", "Cancel check", "command", "blue", "macro", "", [new("text", "should never type", 5000)]));
                runner.SetSoundboardOnly(true);
                runner.SetSoundboardOnly(false);
                await Assert.ThrowsAnyAsync<OperationCanceledException>(() => pending);
                runner.SetSoundboardOnly(true);
                Assert.True(new StateStore(folder).State.SoundboardOnly);
                Assert.Contains("audio-monitor-v1", server.Snapshot().Capabilities!);
                var monitorResponse = await client.PutAsJsonAsync("/api/audio", new AudioSettings("", .6f, true, "", .3f), Wire.Json);
                monitorResponse.EnsureSuccessStatusCode();
                var monitored = (await monitorResponse.Content.ReadFromJsonAsync<Snapshot>(Wire.Json))!;
                Assert.True(monitored.MonitorEnabled);
                Assert.Equal(.3f, monitored.MonitorVolume);
                Assert.True(new StateStore(folder).State.MonitorEnabled);
                (await client.PutAsJsonAsync("/api/audio", new AudioSettings("", .5f), Wire.Json)).EnsureSuccessStatusCode();
                Assert.True(server.Snapshot().MonitorEnabled);
                Assert.Equal(.3f, server.Snapshot().MonitorVolume);
                Assert.Equal(HttpStatusCode.BadRequest, (await client.PutAsJsonAsync("/api/audio", new AudioSettings("", .5f, true, "missing-device"), Wire.Json)).StatusCode);
                (await client.PutAsJsonAsync("/api/audio", new AudioSettings("", .75f, false), Wire.Json)).EnsureSuccessStatusCode();
                snapshot = server.Snapshot();
                Assert.Equal(CompanionBuild.Version, snapshot.CompanionVersion);
                Assert.True(Version.TryParse(snapshot.CompanionVersion!.Split('-')[0], out _));
                Assert.Contains("soundboard-playback-v1", snapshot.Capabilities!);
                Assert.Contains("soundboard-queue-v1", snapshot.Capabilities!);
                Assert.Contains("soundboard-queue-edit-v1", snapshot.Capabilities!);
                Assert.Contains("clip-audio-v1", snapshot.Capabilities!);
                var previewClip = snapshot.Clips.First();
                var previewAudio = await client.GetAsync($"/api/clips/{previewClip.Id}/audio");
                previewAudio.EnsureSuccessStatusCode();
                Assert.Equal("audio/wav", previewAudio.Content.Headers.ContentType?.MediaType);
                Assert.Equal(await File.ReadAllBytesAsync(store.ClipPath(previewClip.Id)), await previewAudio.Content.ReadAsByteArrayAsync());
                Assert.Equal(HttpStatusCode.BadRequest, (await client.GetAsync("/api/clips/missing/audio")).StatusCode);
                var playback = (await client.GetFromJsonAsync<PlaybackState>("/api/playback", Wire.Json))!;
                Assert.Empty(playback.PadIds);
                Assert.NotNull(playback.QueuedPadIds);
                Assert.Empty(playback.QueuedPadIds);
                Assert.False(string.IsNullOrWhiteSpace(playback.SessionId));
                var clearQueue = await client.PutAsJsonAsync("/api/queue", new QueueUpdate("clear", playback.SessionId, playback.Revision), Wire.Json);
                clearQueue.EnsureSuccessStatusCode();
                var cleared = (await client.GetFromJsonAsync<PlaybackState>("/api/playback", Wire.Json))!;
                Assert.True(cleared.Revision > playback.Revision);
                Assert.Empty(cleared.QueuedPadIds!);
                Assert.Equal(HttpStatusCode.Conflict, (await client.PutAsJsonAsync("/api/queue", new QueueUpdate("move", playback.SessionId, playback.Revision, 0, 1), Wire.Json)).StatusCode);
                Assert.Equal(HttpStatusCode.Conflict, (await client.PutAsJsonAsync("/api/queue", new QueueUpdate("clear", "previous-session", cleared.Revision), Wire.Json)).StatusCode);
                Assert.Equal(HttpStatusCode.BadRequest, (await client.PutAsJsonAsync("/api/queue", new QueueUpdate("remove", cleared.SessionId, cleared.Revision, 0), Wire.Json)).StatusCode);
                Assert.Equal(HttpStatusCode.BadRequest, (await client.PostAsJsonAsync("/api/trigger",
                    new Trigger(snapshot.Decks[0].Pads[0].Id, Guid.NewGuid().ToString(), true, "invalid"), Wire.Json)).StatusCode);
                var decks = snapshot.Decks.ToList();
                decks[0] = decks[0] with { Name = "Game night", SteamAppId = "730", Pads = decks[0].Pads.AsEnumerable().Reverse().ToList() };
                var response = await client.PutAsJsonAsync("/api/decks", new DeckUpdate(snapshot.Version, decks), Wire.Json);
                response.EnsureSuccessStatusCode();
                var saved = (await response.Content.ReadFromJsonAsync<Snapshot>(Wire.Json))!;
                Assert.Equal("Game night", saved.Decks[0].Name);
                Assert.Equal(snapshot.Decks[0].Pads.Last().Id, saved.Decks[0].Pads.First().Id);
                Assert.Equal(HttpStatusCode.Conflict, (await client.PutAsJsonAsync("/api/decks", new DeckUpdate(snapshot.Version, decks), Wire.Json)).StatusCode);
                var reload = new StateStore(folder);
                Assert.Equal("730", reload.State.Decks[0].SteamAppId);
                var invalid = decks.ToList();
                invalid[0] = invalid[0] with { Pads = [new("bad", "Bad", "app", "orange", "app", "not-approved", [])] };
                Assert.Equal(HttpStatusCode.BadRequest, (await client.PutAsJsonAsync("/api/decks", new DeckUpdate(saved.Version, invalid), Wire.Json)).StatusCode);
                Assert.Equal(HttpStatusCode.BadRequest, (await client.PostAsJsonAsync("/api/trigger", new Trigger("does-not-exist", Guid.NewGuid().ToString()), Wire.Json)).StatusCode);
                Assert.Equal(HttpStatusCode.BadRequest, (await client.PostAsync("/api/clips?name=bad&ext=exe", new ByteArrayContent([0, 1, 2]))).StatusCode);
                var clip = saved.Clips.First();
                var renamedResponse = await client.PutAsJsonAsync($"/api/clips/{clip.Id}", new ClipRename(saved.Version, "  Prepare for takeoff  "), Wire.Json);
                renamedResponse.EnsureSuccessStatusCode();
                var renamed = (await renamedResponse.Content.ReadFromJsonAsync<Snapshot>(Wire.Json))!;
                Assert.Equal("Prepare for takeoff", renamed.Clips.Single(c => c.Id == clip.Id).Name);
                Assert.Equal(clip.Duration, renamed.Clips.Single(c => c.Id == clip.Id).Duration);
                Assert.Equal(saved.Decks[0].Pads[0].Value, renamed.Decks[0].Pads[0].Value);
                Assert.Equal(saved.Decks[0].Pads[0].Title, renamed.Decks[0].Pads[0].Title);
                Assert.Equal("Prepare for takeoff", new StateStore(folder).State.Clips.Single(c => c.Id == clip.Id).Name);
                Assert.Equal(HttpStatusCode.Conflict, (await client.PutAsJsonAsync($"/api/clips/{clip.Id}", new ClipRename(saved.Version, "Stale"), Wire.Json)).StatusCode);
                Assert.Equal(HttpStatusCode.BadRequest, (await client.PutAsJsonAsync($"/api/clips/{clip.Id}", new ClipRename(renamed.Version, "  "), Wire.Json)).StatusCode);
                Assert.Equal(HttpStatusCode.BadRequest, (await client.PutAsJsonAsync($"/api/clips/{clip.Id}", new ClipRename(renamed.Version, new string('x', 61)), Wire.Json)).StatusCode);
                Assert.Equal(HttpStatusCode.BadRequest, (await client.PutAsJsonAsync("/api/clips/missing", new ClipRename(renamed.Version, "Missing"), Wire.Json)).StatusCode);
                (await client.PostAsync("/api/stop", null)).EnsureSuccessStatusCode();
                Assert.Contains("bundled-sounds-v1", server.Snapshot().Capabilities!);
                var packSound = SoundPacks.Find("epic-fails", "sad-violin");
                Assert.Contains(server.Snapshot().Clips, c => c.Id == packSound.ClipId);
                Assert.Equal(await File.ReadAllBytesAsync(store.ClipPath(packSound.ClipId)),
                    await client.GetByteArrayAsync($"/api/clips/{packSound.ClipId}/audio"));
                (await client.DeleteAsync($"/api/clips/{packSound.ClipId}")).EnsureSuccessStatusCode();
                Assert.DoesNotContain(new StateStore(folder).State.Clips, c => c.Id == packSound.ClipId);
                Assert.False(File.Exists(store.ClipPath(packSound.ClipId)));
                Assert.Equal(HttpStatusCode.NotFound, (await client.PostAsync("/api/packs/epic-fails/sounds/sad-violin", new ByteArrayContent([]))).StatusCode);
                identity.RotateToken();
                Assert.Equal(HttpStatusCode.Unauthorized, (await client.GetAsync("/api/state")).StatusCode);
                client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", identity.Token);
                (await client.GetAsync("/api/state")).EnsureSuccessStatusCode();
            }
            finally { await server.Stop(); await server.Stop(); }
        }
        finally { Directory.Delete(folder, true); }
    }
}
