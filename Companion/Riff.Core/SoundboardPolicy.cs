namespace Riff.Core;

public static class SoundboardPolicy
{
    public const string BlockedMessage = "Soundboard mode is on. Sounds, deck navigation, and Stop all are available. To use desktop shortcuts, turn off Soundboard mode in the Windows companion’s Controls tab.";

    public static void EnsureAllowed(string kind, bool soundboardOnly)
    {
        if (soundboardOnly && kind is not ("sound" or "deck" or "back" or "stop")) throw new ArgumentException(BlockedMessage);
    }
}
