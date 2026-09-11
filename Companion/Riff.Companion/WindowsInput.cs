using System.ComponentModel;
using System.Runtime.InteropServices;
using Riff.Core;

namespace Riff.Companion;

public static class WindowsInput
{
    [StructLayout(LayoutKind.Sequential)] struct Input { public uint Type; public InputUnion Data; }
    [StructLayout(LayoutKind.Explicit)] struct InputUnion
    {
        [FieldOffset(0)] public KeyboardInput Keyboard;
        [FieldOffset(0)] public MouseInput Mouse;
    }
    [StructLayout(LayoutKind.Sequential)] struct KeyboardInput { public ushort Key, Scan; public uint Flags, Time; public UIntPtr Extra; }
    [StructLayout(LayoutKind.Sequential)] struct MouseInput { public int X, Y; public uint MouseData, Flags, Time; public UIntPtr Extra; }
    [DllImport("user32.dll", SetLastError = true)] static extern uint SendInput(uint count, Input[] inputs, int size);
    [DllImport("user32.dll")] static extern short GetAsyncKeyState(int key);
    static bool Extended(ushort key) => key is 0x5B or 0x21 or 0x22 or 0x23 or 0x24 or 0x25 or 0x26 or 0x27 or 0x28 or 0x2D or 0x2E or >= 0xAD and <= 0xB3;
    static Input Key(ushort code, bool up, bool unicode = false) => new()
    {
        Type = 1, Data = new() { Keyboard = new() { Key = unicode ? (ushort)0 : code, Scan = unicode ? code : (ushort)0,
            Flags = (up ? 2u : 0u) | (unicode ? 4u : Extended(code) ? 1u : 0u) } }
    };
    static void Send(Input[] inputs)
    {
        if (SendInput((uint)inputs.Length, inputs, Marshal.SizeOf<Input>()) != inputs.Length)
            throw new Win32Exception(Marshal.GetLastWin32Error(), "Windows blocked the shortcut. Keep the target app at the same permission level as Riff.");
    }
    public static void Hotkey(string shortcut) => Chord(Hotkeys.Parse(shortcut));
    static void Chord(ushort[] keys)
    {
        if (keys.Any(k => (GetAsyncKeyState(k) & 0x8000) != 0)) throw new ArgumentException("Release the shortcut keys on your keyboard and try again.");
        try { Send(keys.Select(k => Key(k, false)).Concat(keys.Reverse().Select(k => Key(k, true))).ToArray()); }
        catch { SendInput((uint)keys.Length, keys.Reverse().Select(k => Key(k, true)).ToArray(), Marshal.SizeOf<Input>()); throw; }
    }
    public static void Text(string text) => Send(text.SelectMany(c => new[] { Key(c, false, true), Key(c, true, true) }).ToArray());
    public static void Media(string command) => Chord([command switch
    {
        "playPause" => 0xB3, "next" => 0xB0, "previous" => 0xB1,
        "volumeUp" => 0xAF, "volumeDown" => 0xAE, "mute" => 0xAD,
        _ => throw new ArgumentException("Unknown media command.")
    }]);
}
