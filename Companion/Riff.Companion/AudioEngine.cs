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
    readonly List<QueuedSound> queued = [];
    sealed record QueuedSound(string Id, string PadId, string Path, string OutputId, string? MonitorOutputId, float MonitorVolume);
    public event Action<string>? Warning;
    float volume = .75f;
    sealed record AudioRoute(WasapiOut Output, AudioFileReader Reader, MMDevice Device, bool IsMonitor) : IDisposable
    {
        public void Dispose() { try { Output.Dispose(); } finally { try { Reader.Dispose(); } finally { Device.Dispose(); } } }
    }
    sealed record Playback(string Id, string PadId, List<AudioRoute> Routes) : IDisposable
    {
        public HashSet<AudioRoute> Finished { get; } = [];
        public void Dispose()
        {
            List<Exception> errors = [];
            foreach (var route in Routes)
            {
                try { route.Dispose(); }
                catch (Exception error) { errors.Add(error); }
            }
            if (errors.Count > 0) throw new AggregateException("Could not close every audio output.", errors);
        }
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
        lock (gate) { volume = value; foreach (var route in playing.SelectMany(p => p.Routes).Where(r => !r.IsMonitor)) route.Reader.Volume = volume; }
    }
    public void SetMonitorVolume(float value)
    {
        lock (gate)
        {
            foreach (var route in playing.SelectMany(p => p.Routes).Where(r => r.IsMonitor)) route.Reader.Volume = value;
            for (var i = 0; i < queued.Count; i++) queued[i] = queued[i] with { MonitorVolume = value };
        }
    }
    public Riff.Core.PlaybackState Status()
    {
        lock (gate) return new(sessionId, revision, playing.Select(p => p.PadId).Where(id => id.Length > 0).Distinct().ToList(), queued.Select(p => p.PadId).ToList());
    }
    public void Play(string path, string outputId, string padId = "", bool toggle = false, string? mode = null, string? monitorOutputId = null, float monitorVolume = .75f)
    {
        lock (controlGate)
        {
            Playback[] stopped;
            PlaybackPlan plan;
            lock (gate)
            {
                var selectedMode = mode ?? soundMode;
                plan = PlaybackPolicy.Plan(playing.Select(p => new ActiveSound(p.Id, p.PadId)).ToList(), padId, toggle, selectedMode,
                    queued.Select(p => new ActiveSound(p.Id, p.PadId)).ToList());
                soundMode = selectedMode;
                stopped = playing.Where(p => plan.StopIds.Contains(p.Id)).ToArray();
                foreach (var item in stopped) playing.Remove(item);
                var removed = queued.RemoveAll(p => plan.RemoveQueuedIds?.Contains(p.Id) == true);
                if (plan.Enqueue) queued.Add(new(Guid.NewGuid().ToString("N"), padId, path, outputId, monitorOutputId, monitorVolume));
                if (stopped.Length > 0 || removed > 0 || plan.Enqueue) revision++;
            }
            Stop(stopped);
            if (plan.Start) Start(path, outputId, padId, monitorOutputId, monitorVolume);
            else StartNext();
        }
    }
    // Called with controlGate held so completion and Stop All cannot race a new start.
    void Start(string path, string outputId, string padId, string? monitorOutputId, float monitorVolume)
    {
        using var enumerator = new MMDeviceEnumerator();
        var primary = CreateRoute(enumerator, path, outputId, volume, false);
        var playback = new Playback(Guid.NewGuid().ToString("N"), padId, [primary]);
        try
        {
            if (monitorOutputId is not null)
            {
                try
                {
                    // Compare resolved endpoints: "PC default" may be the selected primary device.
                    var device = ResolveDevice(enumerator, monitorOutputId);
                    if (device.ID == primary.Device.ID) device.Dispose();
                    else playback.Routes.Add(CreateRoute(device, path, monitorVolume, true));
                }
                catch (Exception error) { ReportMonitorFailure(error); }
            }
            foreach (var route in playback.Routes)
            {
                route.Output.PlaybackStopped += (_, args) =>
                {
                    // Dispose off NAudio's render thread, which it joins.
                    ThreadPool.QueueUserWorkItem(_ =>
                    {
                        lock (controlGate)
                        {
                            bool finished;
                            lock (gate)
                            {
                                if (!playing.Contains(playback) || !playback.Routes.Contains(route)) return;
                                playback.Finished.Add(route);
                                finished = playback.Finished.Count == playback.Routes.Count;
                                if (finished) { playing.Remove(playback); revision++; }
                            }
                            if (args.Exception is not null && route.IsMonitor) ReportMonitorFailure(args.Exception);
                            if (!finished) return;
                            try { playback.Dispose(); }
                            catch (Exception error) { System.Diagnostics.Trace.TraceError("Audio cleanup failed: {0}", error); }
                            StartNext();
                        }
                    });
                };
            }
            lock (gate) { primary.Reader.Volume = volume; playing.Add(playback); revision++; }
            primary.Output.Play();
            foreach (var route in playback.Routes.Where(r => r.IsMonitor).ToArray())
            {
                try { route.Output.Play(); }
                catch (Exception error)
                {
                    lock (gate) playback.Routes.Remove(route);
                    try { route.Dispose(); }
                    catch (Exception cleanup) { System.Diagnostics.Trace.TraceError("Audio cleanup failed: {0}", cleanup); }
                    ReportMonitorFailure(error);
                }
            }
        }
        catch
        {
            lock (gate) { if (playing.Remove(playback)) revision++; }
            playback.Dispose();
            throw;
        }
    }
    static MMDevice ResolveDevice(MMDeviceEnumerator enumerator, string id) =>
        id == "" ? enumerator.GetDefaultAudioEndpoint(DataFlow.Render, Role.Multimedia) : enumerator.GetDevice(id);
    static AudioRoute CreateRoute(MMDeviceEnumerator enumerator, string path, string id, float volume, bool monitor) =>
        CreateRoute(ResolveDevice(enumerator, id), path, volume, monitor);
    static AudioRoute CreateRoute(MMDevice device, string path, float volume, bool monitor)
    {
        AudioFileReader? reader = null;
        WasapiOut? output = null;
        try
        {
            reader = new AudioFileReader(path) { Volume = volume };
            output = new WasapiOut(device, AudioClientShareMode.Shared, true, 40);
            output.Init(reader);
            return new(output, reader, device, monitor);
        }
        catch
        {
            try { output?.Dispose(); }
            finally { try { reader?.Dispose(); } finally { device.Dispose(); } }
            throw;
        }
    }
    void ReportMonitorFailure(Exception error)
    {
        var message = "Could not play through your headphones. Check the Hear sounds myself output: " + error.Message;
        System.Diagnostics.Trace.TraceWarning(message);
        try { Warning?.Invoke(message); }
        catch (Exception notification) { System.Diagnostics.Trace.TraceError("Audio warning failed: {0}", notification); }
    }
    void StartNext()
    {
        while (true)
        {
            QueuedSound next;
            lock (gate)
            {
                if (playing.Count > 0 || queued.Count == 0) return;
                next = queued[0]; queued.RemoveAt(0); revision++;
            }
            try { Start(next.Path, next.OutputId, next.PadId, next.MonitorOutputId, next.MonitorVolume); return; }
            catch (Exception error) { System.Diagnostics.Trace.TraceError("Queued sound failed: {0}", error); }
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
            lock (gate)
            {
                items = playing.ToArray(); playing.Clear();
                if (items.Length > 0 || queued.Count > 0) revision++;
                queued.Clear();
            }
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
