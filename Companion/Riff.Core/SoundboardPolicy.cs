namespace Riff.Core;

public static class SoundboardPolicy
{
    public const string BlockedMessage = "Soundboard mode is on. Only sound buttons can run. To use desktop shortcuts, turn off Soundboard mode in the Windows companion’s Controls tab.";

    public static void EnsureAllowed(string kind, bool soundboardOnly)
    {
        if (soundboardOnly && kind != "sound") throw new ArgumentException(BlockedMessage);
    }
}
