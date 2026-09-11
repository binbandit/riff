namespace Riff.Companion;

internal static class Program
{
    [STAThread]
    static void Main()
    {
        using var mutex = new Mutex(true, @"Local\Riff.Companion", out var created);
        if (!created) { MessageBox.Show("Riff is already running. Open it from your system tray.", "Riff"); return; }
        ApplicationConfiguration.Initialize();
        Application.ThreadException += (_, args) => MessageBox.Show(args.Exception.Message, "Riff needs attention", MessageBoxButtons.OK, MessageBoxIcon.Error);
        try
        {
            var folder = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Riff");
            var store = new StateStore(folder);
            using var identity = new PairingIdentity(folder);
            using var audio = new AudioEngine(); audio.SetVolume(store.State.Volume);
            using var runner = new ActionRunner(store, audio);
            var server = new CompanionServer(store, identity, audio, runner);
            Application.Run(new MainForm(store, identity, audio, runner, server));
        }
        catch (Exception ex) { MessageBox.Show(ex.Message, "Riff could not start", MessageBoxButtons.OK, MessageBoxIcon.Error); }
    }
}
