using Riff.Core;
using QRCoder;

namespace Riff.Companion;

public sealed class MainForm : Form
{
    static readonly Color BackgroundColor = Color.FromArgb(14, 16, 20);
    static readonly Color PanelColor = Color.FromArgb(24, 28, 34);
    static readonly Color Accent = Color.FromArgb(255, 140, 79);
    readonly StateStore store;
    readonly PairingIdentity identity;
    readonly AudioEngine audio;
    readonly ActionRunner runner;
    readonly CompanionServer server;
    readonly NotifyIcon tray;
    readonly System.Windows.Forms.Timer timer = new() { Interval = 2000 };
    readonly Label status = new() { AutoSize = true, ForeColor = Color.Silver };
    readonly TextBox pairingLink = new() { Multiline = true, ReadOnly = true, Height = 86, Dock = DockStyle.Top, ScrollBars = ScrollBars.Vertical };
    readonly ComboBox addresses = new() { DropDownStyle = ComboBoxStyle.DropDownList, Width = 240 };
    readonly PictureBox qr = new() { Width = 280, Height = 280, SizeMode = PictureBoxSizeMode.Zoom, BackColor = Color.White, Margin = new Padding(16) };
    readonly ComboBox outputs = new() { DropDownStyle = ComboBoxStyle.DropDownList, Width = 580, DisplayMember = "Name", ValueMember = "Id" };
    readonly TrackBar volume = new() { Minimum = 0, Maximum = 100, TickFrequency = 10, Width = 400 };
    readonly ListBox apps = new() { Height = 220, Dock = DockStyle.Top, DisplayMember = "Name" };
    readonly TextBox log = new() { Multiline = true, ReadOnly = true, Dock = DockStyle.Fill, ScrollBars = ScrollBars.Vertical };
    bool exiting;
    bool stopping;
    bool serverStarted;
    public MainForm(StateStore store, PairingIdentity identity, AudioEngine audio, ActionRunner runner, CompanionServer server)
    {
        this.store = store; this.identity = identity; this.audio = audio; this.runner = runner; this.server = server;
        Text = $"Riff {CompanionBuild.Version} · Windows companion"; Size = new(950, 800); MinimumSize = new(780, 650);
        StartPosition = FormStartPosition.CenterScreen; BackColor = BackgroundColor; ForeColor = Color.White;
        Font = new("Segoe UI", 10); Icon = SystemIcons.Application;
        var layout = new TableLayoutPanel { Dock = DockStyle.Fill, RowCount = 3, ColumnCount = 1, Padding = new(24) };
        layout.RowStyles.Add(new(SizeType.Absolute, 88)); layout.RowStyles.Add(new(SizeType.Percent, 100)); layout.RowStyles.Add(new(SizeType.Absolute, 46));
        var header = new FlowLayoutPanel { Dock = DockStyle.Fill };
        header.Controls.Add(new Label { Text = "riff", Font = new("Segoe UI", 32, FontStyle.Bold), ForeColor = Accent, AutoSize = true });
        header.Controls.Add(new Label { Text = "YOUR IPAD. YOUR CONTROL ROOM.\nWindows companion", AutoSize = true, ForeColor = Color.Silver, Margin = new(24, 17, 0, 0) });
        var tabs = new TabControl { Dock = DockStyle.Fill, Padding = new(22, 10) };
        tabs.TabPages.Add(PairPage()); tabs.TabPages.Add(AudioPage()); tabs.TabPages.Add(AppsPage());
        var activity = new TabPage("Activity") { BackColor = PanelColor, Padding = new(18) }; activity.Controls.Add(log); tabs.TabPages.Add(activity);
        layout.Controls.Add(header, 0, 0); layout.Controls.Add(tabs, 0, 1);
        var footer = new FlowLayoutPanel { Dock = DockStyle.Fill, Padding = new(0, 12, 0, 0) }; footer.Controls.Add(status); layout.Controls.Add(footer, 0, 2); Controls.Add(layout);
        // Data-bound lists need the form's BindingContext before selecting an item.
        RefreshOutputs();
        var menu = new ContextMenuStrip();
        menu.Items.Add("Open Riff", null, (_, _) => ShowWindow());
        menu.Items.Add("Stop all sounds", null, (_, _) => runner.Stop());
        menu.Items.Add("Quit Riff", null, (_, _) => { exiting = true; Close(); });
        tray = new NotifyIcon { Icon = Icon, Text = "Riff · Ready for your iPad", Visible = true, ContextMenuStrip = menu };
        tray.DoubleClick += (_, _) => ShowWindow();
        server.Activity += AddLog;
        timer.Tick += (_, _) => { status.Text = !serverStarted ? "Companion offline - check Activity" : DateTime.UtcNow - server.LastSeen < TimeSpan.FromSeconds(12) ? "●  iPad connected · Encrypted local connection" : "Waiting for your iPad · Port 49321 · Private network only"; };
        Shown += async (_, _) =>
        {
            try { await server.Start(); serverStarted = true; AddLog("Companion ready. Pair your iPad in the Connect tab."); }
            catch (Exception ex) { AddLog("Could not start: " + ex.Message); MessageBox.Show(this, ex.Message, "Connection could not start"); }
            timer.Start();
        };
        FormClosing += HandleClosing;
        ApplyColors(this);
    }
    TabPage PairPage()
    {
        var page = new TabPage("Connect iPad") { BackColor = PanelColor, Padding = new(22), AutoScroll = true };
        var flow = Flow();
        flow.Controls.Add(Heading("Meet your other half."));
        flow.Controls.Add(Body("Connect both devices to the same home network. On your iPad, open Riff and tap Connect your PC. Scan this code or paste the pairing link."));
        var row = new FlowLayoutPanel { AutoSize = true, Width = 790 };
        row.Controls.Add(new Label { Text = "PC network address", AutoSize = true, Margin = new(0, 8, 12, 0) });
        foreach (var address in PairingIdentity.Addresses()) addresses.Items.Add(address);
        if (addresses.Items.Count == 0) addresses.Items.Add(Environment.MachineName);
        addresses.SelectedIndex = 0; addresses.SelectedIndexChanged += (_, _) => RefreshPairing(); row.Controls.Add(addresses);
        row.Controls.Add(Button("Refresh addresses", () => { addresses.Items.Clear(); foreach (var address in PairingIdentity.Addresses()) addresses.Items.Add(address); if (addresses.Items.Count == 0) addresses.Items.Add(Environment.MachineName); addresses.SelectedIndex = 0; }));
        flow.Controls.Add(row);
        flow.Controls.Add(qr);
        pairingLink.Width = 740; pairingLink.Dock = DockStyle.None; flow.Controls.Add(pairingLink);
        var buttons = new FlowLayoutPanel { AutoSize = true, Width = 790 };
        buttons.Controls.Add(Button("Copy pairing link", () => { Clipboard.SetText(pairingLink.Text); AddLog("Pairing link copied. Keep this link private."); }));
        buttons.Controls.Add(Button("Revoke paired devices", () =>
        {
            if (MessageBox.Show(this, "Disconnect every paired iPad? You will need to scan a new pairing code.", "Revoke pairing", MessageBoxButtons.OKCancel) != DialogResult.OK) return;
            identity.RotateToken(); runner.Stop(); RefreshPairing(); AddLog("Pairing revoked. Reconnect using the new link.");
        })); flow.Controls.Add(buttons);
        flow.Controls.Add(Body("If Windows asks about firewall access, allow Private networks. If several addresses appear, choose the address of your home Wi-Fi or Ethernet, not a VPN. Do not forward this port on your router."));
        page.Controls.Add(flow); RefreshPairing(); return page;
    }
    TabPage AudioPage()
    {
        var page = new TabPage("Audio & voice chat") { BackColor = PanelColor, Padding = new(22), AutoScroll = true };
        var flow = Flow(); flow.Controls.Add(Heading("Let your sounds do the talking."));
        flow.Controls.Add(Body("For game voice chat, install VB-CABLE, choose CABLE Input below, and choose CABLE Output as the microphone in your game or Discord."));
        flow.Controls.Add(outputs); volume.Value = (int)(store.State.Volume * 100); flow.Controls.Add(volume);
        var buttons = new FlowLayoutPanel { AutoSize = true, Width = 790 };
        buttons.Controls.Add(Button("Apply output & volume", () =>
        {
            if (outputs.SelectedItem is not DeviceInfo device) return;
            lock (store.Gate) store.Save(store.State with { OutputId = device.Id, Volume = volume.Value / 100f, Version = store.State.Version + 1 });
            audio.SetVolume(volume.Value / 100f); AddLog("Audio output updated: " + device.Name);
        }));
        buttons.Controls.Add(Button("Refresh devices", RefreshOutputs));
        buttons.Controls.Add(Button("Test sound", () => { lock (store.Gate) { var clip = store.State.Clips.FirstOrDefault(); if (clip is not null) audio.Play(store.ClipPath(clip.Id), store.State.OutputId); } }));
        buttons.Controls.Add(Button("Stop all", runner.Stop)); flow.Controls.Add(buttons);
        flow.Controls.Add(Heading("A quick voice-chat check"));
        flow.Controls.Add(Body("1. Apply the selected output, then play a test sound.\n\n2. In your chat app, select CABLE Output as the microphone and open its microphone test.\n\n3. Use voice activation, or hold the game's push-to-talk key while the clip plays.\n\n4. If clips are cut off, lower the voice threshold and disable noise suppression.\n\nTo hear the clips yourself, open Windows Sound > More sound settings > Recording > CABLE Output > Properties > Listen. Enable Listen to this device and select your headphones. This may add monitoring latency."));
        flow.Controls.Add(Button("Open VB-CABLE website", () => System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo("https://vb-audio.com/Cable/") { UseShellExecute = true })));
        flow.Controls.Add(Button("Import sound from PC", () =>
        {
            using var dialog = new OpenFileDialog { Filter = "Audio files|*.wav;*.mp3;*.m4a;*.aac;*.aiff;*.aif", Title = "Import a sound (up to 60 seconds, 20 MB)" };
            if (dialog.ShowDialog(this) != DialogResult.OK) return;
            if (new FileInfo(dialog.FileName).Length > 20 * 1024 * 1024) throw new ArgumentException("Choose a file smaller than 20 MB.");
            var clip = AudioEngine.Import(dialog.FileName, Path.GetFileNameWithoutExtension(dialog.FileName), store); AddLog("Imported: " + clip.Name);
        }));
        page.Controls.Add(flow); return page;
    }
    TabPage AppsPage()
    {
        var page = new TabPage("Allowed apps") { BackColor = PanelColor, Padding = new(22) };
        var flow = Flow(); flow.Controls.Add(Heading("Your shortcuts. Your rules."));
        flow.Controls.Add(Body("Add the Windows applications your iPad can launch. Then choose Launch app when creating a button on your iPad. Riff does not accept shell commands from your iPad."));
        apps.Width = 700; apps.Dock = DockStyle.None; RefreshApps(); flow.Controls.Add(apps);
        var row = new FlowLayoutPanel { AutoSize = true };
        row.Controls.Add(Button("Add application", () =>
        {
            using var dialog = new OpenFileDialog { Filter = "Windows applications|*.exe", Title = "Allow an application" };
            if (dialog.ShowDialog(this) == DialogResult.OK) { store.AddApp(dialog.FileName); RefreshApps(); }
        }));
        row.Controls.Add(Button("Remove selected", () => { if (apps.SelectedItem is LaunchTarget target) { store.RemoveApp(target.Id); RefreshApps(); } }));
        flow.Controls.Add(row);
        flow.Controls.Add(Body("Keyboard shortcuts, typed text, websites, media controls, and multi-step sequences are configured on the iPad. Shortcuts are sent to whichever Windows app is focused. Some games block simulated keyboard input.\n\nSteam game detection is automatic when Steam is running. Link a game to a deck on your iPad. No Steam login or API key is required."));
        page.Controls.Add(flow); return page;
    }
    void RefreshPairing()
    {
        if (addresses.SelectedItem is not string address) return;
        pairingLink.Text = identity.Link(address);
        using var generator = new QRCodeGenerator(); using var data = generator.CreateQrCode(pairingLink.Text, QRCodeGenerator.ECCLevel.M);
        using var code = new QRCode(data); var old = qr.Image; qr.Image = code.GetGraphic(6); old?.Dispose();
    }
    void RefreshOutputs()
    {
        outputs.DataSource = audio.Devices(); outputs.SelectedValue = store.State.OutputId;
        if (outputs.SelectedIndex < 0) { outputs.SelectedIndex = 0; AddLog("Saved audio output is disconnected. Choose and apply another output."); }
    }
    void RefreshApps() { lock (store.Gate) apps.DataSource = store.State.Apps.ToList(); }
    static FlowLayoutPanel Flow() => new() { Dock = DockStyle.Fill, FlowDirection = FlowDirection.TopDown, WrapContents = false, AutoScroll = true };
    static Label Heading(string text) => new() { Text = text, Font = new("Segoe UI", 20, FontStyle.Bold), AutoSize = true, Margin = new(0, 8, 0, 16) };
    static Label Body(string text) => new() { Text = text, AutoSize = true, MaximumSize = new(720, 0), ForeColor = Color.Silver, Margin = new(0, 0, 0, 18) };
    Button Button(string text, Action action)
    {
        var button = new Button { Text = text, AutoSize = true, FlatStyle = FlatStyle.Flat, Padding = new(10, 6, 10, 6), Margin = new(0, 6, 10, 10), BackColor = Accent, ForeColor = BackgroundColor };
        button.FlatAppearance.BorderSize = 0;
        button.Click += (_, _) => { try { action(); } catch (Exception ex) { AddLog(ex.Message); MessageBox.Show(this, ex.Message, "Riff needs attention"); } }; return button;
    }
    static void ApplyColors(Control parent)
    {
        foreach (Control control in parent.Controls)
        {
            if (control is TextBox or ListBox or ComboBox) { control.BackColor = Color.FromArgb(34, 39, 46); control.ForeColor = Color.White; }
            ApplyColors(control);
        }
    }
    void AddLog(string message)
    {
        if (IsDisposed || Disposing) return;
        if (InvokeRequired) { BeginInvoke(() => AddLog(message)); return; }
        if (log.TextLength > 30000) log.Text = log.Text[^15000..];
        log.AppendText($"{DateTime.Now:HH:mm:ss}  {message}{Environment.NewLine}");
    }
    void ShowWindow() { Show(); WindowState = FormWindowState.Normal; Activate(); }
    async void HandleClosing(object? sender, FormClosingEventArgs args)
    {
        if (stopping) return;
        args.Cancel = true;
        if (!exiting) { Hide(); tray.ShowBalloonTip(2000, "Riff is still running", "Open Riff from the system tray. Choose Quit Riff there to exit.", ToolTipIcon.Info); return; }
        Enabled = false; timer.Stop();
        await server.Stop(); stopping = true; Close();
    }
    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            server.Activity -= AddLog;
            tray?.Dispose(); timer.Dispose();
            var image = qr.Image; qr.Image = null; image?.Dispose();
        }
        base.Dispose(disposing);
    }
}
