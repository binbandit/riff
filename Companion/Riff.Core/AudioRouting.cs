namespace Riff.Core;

public static class AudioRouting
{
    public static SavedState Apply(SavedState state, AudioSettings settings, IReadOnlyList<DeviceInfo> devices)
    {
        var enabled = settings.MonitorEnabled ?? state.MonitorEnabled;
        var monitor = settings.MonitorOutputId ?? state.MonitorOutputId;
        var monitorVolume = settings.MonitorVolume ?? state.MonitorVolume;
        if (!float.IsFinite(settings.Volume) || settings.Volume is < 0 or > 1 ||
            !float.IsFinite(monitorVolume) || monitorVolume is < 0 or > 1)
            throw new ArgumentException("Volume must be between 0 and 100%.");
        if (!devices.Any(d => d.Id == settings.OutputId))
            throw new ArgumentException("This audio output is disconnected. Choose another output.");
        if (enabled && !devices.Any(d => d.Id == monitor))
            throw new ArgumentException("Your headphone output is disconnected. Choose another output or turn off Hear sounds myself.");
        return state with
        {
            OutputId = settings.OutputId, Volume = settings.Volume,
            MonitorEnabled = enabled, MonitorOutputId = monitor, MonitorVolume = monitorVolume,
            Version = state.Version + 1
        };
    }
}
