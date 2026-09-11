using NAudio.CoreAudioApi;
using NAudio.Wave;
using Riff.Core;

namespace Riff.Companion;

public sealed class AudioEngine : IDisposable
{
    readonly object gate = new();
    readonly List<Playback> playing = [];
    float volume = .75f;
    sealed record Playback(WasapiOut Output, AudioFileReader Reader, MMDevice Device) : IDisposable
    {
        public void Dispose() { Output.Dispose(); Reader.Dispose(); Device.Dispose(); }
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
    public void Play(string path, string outputId)
    {
        lock (gate)
        {
            if (playing.Count >= 16) throw new ArgumentException("16 sounds are already playing. Stop a few before starting another.");
            using var enumerator = new MMDeviceEnumerator();
            var device = outputId == "" ? enumerator.GetDefaultAudioEndpoint(DataFlow.Render, Role.Multimedia) : enumerator.GetDevice(outputId);
            AudioFileReader? reader = null;
            WasapiOut? output = null;
            try
            {
                reader = new AudioFileReader(path) { Volume = volume };
                output = new WasapiOut(device, AudioClientShareMode.Shared, true, 40);
                var playback = new Playback(output, reader, device);
                output.Init(reader);
                output.PlaybackStopped += (_, _) => { lock (gate) { if (playing.Remove(playback)) playback.Dispose(); } };
                playing.Add(playback);
                output.Play();
            }
            catch
            {
                playing.RemoveAll(p => ReferenceEquals(p.Output, output));
                output?.Dispose(); reader?.Dispose(); device.Dispose(); throw;
            }
        }
    }
    public void StopAll()
    {
        Playback[] items;
        lock (gate) { items = playing.ToArray(); playing.Clear(); }
        foreach (var item in items) { item.Output.Stop(); item.Dispose(); }
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
