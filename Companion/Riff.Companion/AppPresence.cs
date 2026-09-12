using System.Diagnostics;
using System.Runtime.InteropServices;
using Riff.Core;

namespace Riff.Companion;

public static class AppPresence
{
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);

    public static string Read(IReadOnlyList<LaunchTarget> apps)
    {
        try
        {
            GetWindowThreadProcessId(GetForegroundWindow(), out var id);
            if (id == 0) return "";
            using var process = Process.GetProcessById(checked((int)id));
            var path = process.MainModule?.FileName;
            return apps.FirstOrDefault(a => string.Equals(a.Path, path, StringComparison.OrdinalIgnoreCase))?.Id ?? "";
        }
        catch (Exception error) when (error is System.ComponentModel.Win32Exception or InvalidOperationException or ArgumentException or NotSupportedException or OverflowException)
        { return ""; }
    }
}
