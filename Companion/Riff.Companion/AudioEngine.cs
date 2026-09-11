using NAudio.CoreAudioApi;
using NAudio.Wave;
using Riff.Core;

namespace Riff.Companion;

public sealed class AudioEngine : IDisposable
{
    readonly object gate = new();
    readonly object controlGate = new();
    readonly string sessionId = Guid.NewGuid().ToString("N");
    long revision;
    string soundMode = "overlap";
    readonly List<Playback> playing = [];
    float volume = .75f;
    sealed record Playback(string Id, string PadId, WasapiOut Output, AudioFileReader Reader, MMDevice Device) : IDisposable
    {
        public void Dispose() { try { Output.Dispose(); } finally { try { Reader.Dispose(); } finally { Device.Dispose(); } } }
    }
    public List<DeviceInfo> Devices()
    {
        using var enumerator = new MMDeviceEnumerator();
        var result = new List<DeviceInfo> { new("", "PC default output") };
        foreach (var device in enumerator.EnumerateAudioEndPoints(DataFlow.Render, DeviceState.Active))
        { using (device) result.Add(new(device.ID, device.FriendlyName)); }
        return result;
    }
    public void SetVolume(float value)
    {
        lock (gate) { volume = value; foreach (var item in playing) item.Reader.Volume = volume; }
    }
    public Riff.Core.PlaybackState Status()
    {
        lock (gate) return new(sessionId, revision, playing.Select(p => p.PadId).Where(id => id.Length > 0).Distinct().ToList());
    }
    public void Play(string path, string outputId, string padId = "", bool toggle = false, string? mode = null)
    {
        lock (controlGate)
        {
            Playback[] stopped;
            PlaybackPlan plan;
            lock (gate)
            {
                var selectedMode = mode ?? soundMode;
                plan = PlaybackPolicy.Plan(playing.Select(p => new ActiveSound(p.Id, p.PadId)).ToList(), padId, toggle, selectedMode);
                soundMode = selectedMode;
                stopped = playing.Where(p => plan.StopIds.Contains(p.Id)).ToArray();
                foreach (var item in stopped) playing.Remove(item);
                if (stopped.Length > 0) revision++;
            }
            Stop(stopped);
            if (!plan.Start) return;
            using var enumerator = new MMDeviceEnumerator();
            var device = outputId == "" ? enumerator.GetDefaultAudioEndpoint(DataFlow.Render, Role.Multimedia) : enumerator.GetDevice(outputId);
            AudioFileReader? reader = null;
            WasapiOut? output = null;
            var registered = false;
            try
            {
                reader = new AudioFileReader(path) { Volume = volume };
                output = new WasapiOut(device, AudioClientShareMode.Shared, true, 40);
                var playback = new Playback(Guid.NewGuid().ToString("N"), padId, output, reader, device);
                output.Init(reader);
                output.PlaybackStopped += (_, _) =>
                {
                    bool removed;
                    lock (gate) { removed = playing.Remove(playback); if (removed) revision++; }
                    // NAudio can invoke this on its render thread; Dispose joins that thread.
                    if (removed) ThreadPool.QueueUserWorkItem(_ =>
                    {
                        try { playback.Dispose(); }
                        catch (Exception error) { System.Diagnostics.Trace.TraceError("Audio cleanup failed: {0}", error); }
                    });
                };
                lock (gate) { reader.Volume = volume; playing.Add(playback); revision++; registered = true; }
                output.Play();
            }
            catch
            {
                bool owned;
                lock (gate) { owned = playing.RemoveAll(p => ReferenceEquals(p.Output, output)) > 0; if (owned) revision++; }
                // Before registering playback, this method still owns all resources.
                if (!registered || owned) { output?.Dispose(); reader?.Dispose(); device.Dispose(); }
                throw;
            }
        }
    }
    static void Stop(IEnumerable<Playback> items)
    {
        List<Exception> errors = [];
        foreach (var item in items)
        {
            try { item.Dispose(); }
            catch (Exception error) { errors.Add(error); }
        }
        if (errors.Count > 0) throw new AggregateException("Could not close every audio output.", errors);
    }
    public void StopAll()
    {
        lock (controlGate)
        {
            Playback[] items;
            lock (gate) { items = playing.ToArray(); playing.Clear(); if (items.Length > 0) revision++; }
            Stop(items);
        }
    }
    public void Dispose() => StopAll();

    public static Clip Import(string source, string name, StateStore store)
    {
        Rules.CheckText(name, 60, "Sound name");
        lock (store.Gate)
        {
            if (store.State.Clips.Count >= 500) throw new ArgumentException("The library can hold up to 500 sounds.");
        }
        var id = Guid.NewGuid().ToString("N");
        var destination = store.ClipPath(id);
        try
        {
            using (var reader = new AudioFileReader(source))
            {
                if (reader.TotalTime.TotalSeconds is <= 0 or > 60) throw new ArgumentException("Sounds must be between 0 and 60 seconds long.");
                // Normalize uploads to PCM WAV for consistent playback and bounded disk usage.
                var format = new WaveFormat(44100, 16, 1);
                using var resampler = new MediaFoundationResampler(reader, format);
                using var writer = new WaveFileWriter(destination, format);
                var buffer = new byte[16384];
                var total = 0;
                int read;
                while ((read = resampler.Read(buffer, 0, buffer.Length)) > 0)
                {
                    total += read;
                    if (total > 44100 * 2 * 60) throw new ArgumentException("Sounds must be at most 60 seconds long.");
                    writer.Write(buffer, 0, read);
                }
            }
            using var normalized = new WaveFileReader(destination);
            var clip = new Clip(id, name.Trim(), normalized.TotalTime.TotalSeconds);
            lock (store.Gate)
            {
                if (store.State.Clips.Count >= 500) throw new ArgumentException("The library is full.");
                store.Save(store.State with { Clips = [.. store.State.Clips, clip], Version = store.State.Version + 1 });
            }
            return clip;
        }
        catch { File.Delete(destination); throw; }
    }
}
