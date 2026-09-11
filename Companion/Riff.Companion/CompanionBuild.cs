using System.Reflection;

namespace Riff.Companion;

public static class CompanionBuild
{
    public static string Version { get; } = typeof(CompanionBuild).Assembly
        .GetCustomAttribute<AssemblyInformationalVersionAttribute>()!.InformationalVersion.Split('+')[0];
}
