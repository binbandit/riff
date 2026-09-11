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
                client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", identity.Token);
                var snapshot = (await client.GetFromJsonAsync<Snapshot>("/api/state", Wire.Json))!;
                Assert.Equal(2, snapshot.Decks.Count);
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
                identity.RotateToken();
                Assert.Equal(HttpStatusCode.Unauthorized, (await client.GetAsync("/api/state")).StatusCode);
                client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", identity.Token);
                (await client.GetAsync("/api/state")).EnsureSuccessStatusCode();
            }
            finally { await server.Stop(); }
        }
        finally { Directory.Delete(folder, true); }
    }
}
