using Riff.Core;
using QRCoder;
using static Riff.Companion.CompanionTheme;

namespace Riff.Companion;

public sealed class MainForm : Form
{
    readonly StateStore store;
    readonly PairingIdentity identity;
    readonly AudioEngine audio;
    readonly ActionRunner runner;
    readonly CompanionServer server;
    readonly NotifyIcon tray;
    readonly System.Windows.Forms.Timer timer = new() { Interval = 2000 };
    readonly Label status = Label("Starting companion…", StrongFont);
    readonly Label connectionDetail = Label("Private connection on your network", color: Muted);
    readonly TextBox pairingLink = new() { Multiline = true, AutoSize = false, ReadOnly = true, Height = 76, ScrollBars = ScrollBars.Vertical, AccessibleName = "Private pairing link" };
    readonly ComboBox addresses = new() { DropDownStyle = ComboBoxStyle.DropDownList, AccessibleName = "PC network address" };
    readonly PictureBox qr = new() { Width = 224, Height = 224, SizeMode = PictureBoxSizeMode.Zoom, BackColor = Color.White, AccessibleName = "Scan this pairing code with Riff on your iPad", TabStop = false };
    readonly ComboBox outputs = new() { DropDownStyle = ComboBoxStyle.DropDownList, DisplayMember = "Name", ValueMember = "Id", AccessibleName = "Sound output" };
    readonly CheckBox monitorEnabled = new() { Text = "Hear sounds myself", AutoSize = true, Margin = new(0, 0, 0, 12) };
    readonly ComboBox monitorOutputs = new() { DropDownStyle = ComboBoxStyle.DropDownList, DisplayMember = "Name", ValueMember = "Id", AccessibleName = "Headphone output" };
    readonly TrackBar monitorVolume = new() { Minimum = 0, Maximum = 100, TickStyle = TickStyle.None, AccessibleName = "Headphone volume", BackColor = Surface };
    readonly TrackBar volume = new() { Minimum = 0, Maximum = 100, TickStyle = TickStyle.None, AccessibleName = "Sound volume", BackColor = Surface };
    readonly ListBox apps = new() { Height = 220, DisplayMember = "Name", BorderStyle = BorderStyle.None, BackColor = Surface, ForeColor = Ink, AccessibleName = "Allowed applications", IntegralHeight = false };
    readonly Label emptyApps = Label("No applications yet. Add an app to make it available on your iPad.", color: Muted);
    readonly TextBox log = new() { Multiline = true, AutoSize = false, ReadOnly = true, Dock = DockStyle.Fill, ScrollBars = ScrollBars.Vertical, BorderStyle = BorderStyle.None, BackColor = Surface, ForeColor = Muted, AccessibleName = "Companion activity", Font = new("Consolas", 10) };
    readonly Panel pageHost = new() { Dock = DockStyle.Fill, Margin = Padding.Empty };
    readonly List<(RiffButton Button, Control Page)> navigation = [];
    bool exiting;
    bool stopping;
    bool serverStarted;
    public MainForm(StateStore store, PairingIdentity identity, AudioEngine audio, ActionRunner runner, CompanionServer server)
    {
        this.store = store; this.identity = identity; this.audio = audio; this.runner = runner; this.server = server;
        AutoScaleDimensions = new(96, 96); AutoScaleMode = AutoScaleMode.Dpi;
        Text = $"Riff {CompanionBuild.Version} · Windows companion";
        ClientSize = new(1100, 820); MinimumSize = new(960, 720);
        StartPosition = FormStartPosition.CenterScreen; BackColor = Canvas; ForeColor = Ink;
        Font = BodyFont; Icon = SystemIcons.Application;
        var layout = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 2, RowCount = 1, Margin = Padding.Empty };
        layout.ColumnStyles.Add(new(SizeType.Absolute, 224)); layout.ColumnStyles.Add(new(SizeType.Percent, 100));
        layout.RowStyles.Add(new(SizeType.Percent, 100));
        var sidebar = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 1, RowCount = 3, Padding = new(18, 26, 12, 18), Margin = Padding.Empty };
        sidebar.ColumnStyles.Add(new(SizeType.Percent, 100));
        sidebar.RowStyles.Add(new(SizeType.AutoSize)); sidebar.RowStyles.Add(new(SizeType.Percent, 100)); sidebar.RowStyles.Add(new(SizeType.AutoSize));
        var brand = Stack();
        var wordmark = Label("riff", new Font("Segoe UI", 38, FontStyle.Bold)); wordmark.Margin = new(10, 0, 0, 0);
        var tagline = Label("Your PC. In harmony.", color: Muted); tagline.Margin = new(12, 0, 0, 32);
        Add(brand, wordmark, tagline); sidebar.Controls.Add(brand, 0, 0);
        var links = Stack();
        void AddPage(string title, string glyph, Color tint, Control page)
        {
            var button = new RiffButton(title) { Navigation = true, Glyph = glyph, TileColor = tint, AutoSize = false, Height = 54, Margin = new(0, 0, 0, 6) };
            button.Click += (_, _) => SelectPage(page);
            page.Visible = false; pageHost.Controls.Add(page);
            navigation.Add((button, page)); Add(links, button);
        }
        AddPage("Connect iPad", "\uE8EA", Peach, PairPage());
        AddPage("Audio & voice chat", "\uE767", Blue, AudioPage());
        AddPage("Controls", "\uE713", Purple, ControlsPage());
        AddPage("Allowed apps", "\uE8A7", Green, AppsPage());
        var updates = new CompanionUpdatesView();
        AddPage("Updates", "\uE895", Peach, updates);
        var updatesButton = navigation[^1].Button;
        updates.UpdateAvailable += available => updatesButton.Text = available ? "Updates · New" : "Updates";
        AddPage("Activity", "\uE9D9", Blue, ActivityPage());
        sidebar.Controls.Add(links, 0, 1);
        var connection = new RoundedCard { Dock = DockStyle.Top, Padding = new(16, 16, 16, 6), Margin = Padding.Empty };
        status.Margin = new(0, 0, 0, 8); connectionDetail.Font = new("Segoe UI", 9);
        Add(connection, status, connectionDetail); sidebar.Controls.Add(connection, 0, 2);
        var main = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 1, RowCount = 2, Margin = Padding.Empty };
        main.ColumnStyles.Add(new(SizeType.Percent, 100)); main.RowStyles.Add(new(SizeType.Percent, 100)); main.RowStyles.Add(new(SizeType.AutoSize));
        main.Controls.Add(pageHost, 0, 0);
        var footer = new TableLayoutPanel { Dock = DockStyle.Fill, AutoSize = true, ColumnCount = 2, Padding = new(32, 12, 32, 12), Margin = Padding.Empty };
        footer.ColumnStyles.Add(new(SizeType.Percent, 100)); footer.ColumnStyles.Add(new(SizeType.AutoSize));
        var caption = Label("Windows companion  ·  " + CompanionBuild.Version, color: Muted); caption.Anchor = AnchorStyles.Left; caption.Dock = DockStyle.None; caption.Margin = Padding.Empty;
        footer.Controls.Add(caption, 0, 0);
        var stop = Button("Stop all sounds", runner.Stop); stop.Margin = Padding.Empty; footer.Controls.Add(stop, 1, 0);
        main.Controls.Add(footer, 0, 1);
        layout.Controls.Add(sidebar, 0, 0); layout.Controls.Add(main, 1, 0); Controls.Add(layout);
        SelectPage(navigation[0].Page);
        Shown += async (_, _) => await updates.Check();
        // Data-bound lists need the form's BindingContext before selecting an item.
        RefreshOutputs();
        var menu = new ContextMenuStrip();
        menu.Items.Add("Open Riff", null, (_, _) => ShowWindow());
        menu.Items.Add("Stop all sounds", null, (_, _) => runner.Stop());
        menu.Items.Add("Quit Riff", null, (_, _) => { exiting = true; Close(); });
        tray = new NotifyIcon { Icon = Icon, Text = "Riff · Ready for your iPad", Visible = true, ContextMenuStrip = menu };
        tray.DoubleClick += (_, _) => ShowWindow();
        server.Activity += AddLog;
        audio.Warning += AddLog;
        timer.Tick += (_, _) => RefreshConnectionStatus();
        Shown += async (_, _) =>
        {
            try { await server.Start(); serverStarted = true; AddLog("Companion ready. Pair your iPad in Connect iPad."); }
            catch (Exception ex) { AddLog("Could not start: " + ex.Message); MessageBox.Show(this, ex.Message, "Connection could not start"); }
            RefreshConnectionStatus(); timer.Start();
        };
        FormClosing += HandleClosing;
    }
    void SelectPage(Control page)
    {
        pageHost.SuspendLayout();
        foreach (var item in navigation)
        {
            item.Page.Visible = item.Page == page;
            item.Button.Selected = item.Page == page;
        }
        page.BringToFront(); pageHost.ResumeLayout();
    }
    void RefreshConnectionStatus()
    {
        var connected = serverStarted && DateTime.UtcNow - server.LastSeen < TimeSpan.FromSeconds(12);
        status.Text = !serverStarted ? "Companion offline" : connected ? "iPad connected" : "Ready for your iPad";
        status.ForeColor = !serverStarted ? Accent : connected ? Color.FromArgb(50, 99, 68) : Ink;
        connectionDetail.Text = !serverStarted ? "Open Activity for details." : connected ? "Encrypted connection\nOn your local network" : "Open Riff on your iPad to connect.";
    }
    Panel PairPage()
    {
        var page = Page("Connect iPad", "Meet your other half.", "A little connection. A whole lot of possibility.", out var content);
        var pairing = new RoundedCard();
        var columns = new TableLayoutPanel { AutoSize = true, ColumnCount = 2, Dock = DockStyle.Top, Margin = Padding.Empty, BackColor = Color.Transparent };
        columns.ColumnStyles.Add(new(SizeType.Percent, 45)); columns.ColumnStyles.Add(new(SizeType.Percent, 55));
        var codeArea = new Panel { Height = 248, Dock = DockStyle.Fill, Margin = new(0, 0, 20, 0), BackColor = Surface };
        codeArea.Controls.Add(qr);
        codeArea.Layout += (_, _) =>
        {
            var side = Math.Min(224 * codeArea.DeviceDpi / 96, Math.Min(codeArea.ClientSize.Width, codeArea.ClientSize.Height));
            qr.SetBounds((codeArea.ClientSize.Width - side) / 2, (codeArea.ClientSize.Height - side) / 2, side, side);
        };
        var steps = Stack(); steps.Padding = new(0, 14, 0, 0);
        Add(steps, Label("Let’s get connected", SectionFont),
            Label("1   Join the same Wi-Fi", StrongFont), Body("Connect your iPad and this PC to the same home network."),
            Label("2   Open Riff on your iPad", StrongFont), Body("Tap Connect PC, then scan this code. You’re ready to play."));
        columns.Controls.Add(codeArea, 0, 0); columns.Controls.Add(steps, 1, 0);
        Add(pairing, columns);
        var privacy = Body("This code gives access to your PC controls. Keep it private."); privacy.Margin = new(0, 16, 0, 8);
        Add(pairing, privacy); Add(content, pairing);
        foreach (var address in PairingIdentity.Addresses()) addresses.Items.Add(address);
        if (addresses.Items.Count == 0) addresses.Items.Add(Environment.MachineName);
        addresses.SelectedIndex = 0; addresses.SelectedIndexChanged += (_, _) => RefreshPairing();
        var rawLink = Field(pairingLink); rawLink.Visible = false;
        var showLink = new CheckBox { Text = "Show pairing link", AutoSize = true, Margin = new(0, 4, 0, 12) };
        showLink.CheckedChanged += (_, _) => rawLink.Visible = showLink.Checked;
        var copy = Button("Copy pairing link", () => { Clipboard.SetText(pairingLink.Text); AddLog("Pairing link copied. Keep this link private."); }, primary: true);
        var refresh = Button("Refresh addresses", () =>
        {
            addresses.Items.Clear(); foreach (var address in PairingIdentity.Addresses()) addresses.Items.Add(address);
            if (addresses.Items.Count == 0) addresses.Items.Add(Environment.MachineName); addresses.SelectedIndex = 0;
        });
        Add(content, Card("Connect with a link", Body("Choose this PC’s Wi-Fi or Ethernet address, then paste the link into Riff on your iPad."),
            Label("PC network address", StrongFont), Field(addresses), Actions(copy, refresh), showLink, rawLink));
        var revoke = Button("Revoke paired devices", () =>
        {
            if (MessageBox.Show(this, "Disconnect every paired iPad? You will need to scan a new pairing code.", "Revoke pairing", MessageBoxButtons.OKCancel) != DialogResult.OK) return;
            identity.RotateToken(); runner.Stop(); RefreshPairing(); AddLog("Pairing revoked. Reconnect using the new link.");
        });
        Add(content, Disclosure("Connection help & paired devices", Body("Allow Riff through Windows Firewall on Private networks. Choose your home Wi-Fi or Ethernet address, not a VPN. Guest Wi-Fi can prevent devices from connecting. Never forward port 49321 on your router."),
            Body("Revoke pairing to disconnect all iPads and create a new private code."), Actions(revoke)));
        RefreshPairing(); return page;
    }
    Panel AudioPage()
    {
        var page = Page("Audio & voice chat", "Make yourself heard.", "Send sounds to your game, and a copy to your headphones.", out var content);
        volume.Value = (int)(store.State.Volume * 100);
        monitorEnabled.Checked = store.State.MonitorEnabled;
        monitorVolume.Value = (int)(store.State.MonitorVolume * 100);
        monitorOutputs.Enabled = monitorVolume.Enabled = monitorEnabled.Checked;
        monitorEnabled.CheckedChanged += (_, _) => monitorOutputs.Enabled = monitorVolume.Enabled = monitorEnabled.Checked;
        var soundCard = Card("Sound output", Body("For game chat or Discord, choose CABLE Input. For playback on your PC, choose your speakers or headphones."),
            Label("Play sounds through", StrongFont), Field(outputs), VolumeControl("Sound volume", volume));
        var headphoneCard = Card("Just for your ears", monitorEnabled, Body("Hear a copy through your PC headphones. This volume only changes what you hear."),
            Label("Headphone output", StrongFont), Field(monitorOutputs), VolumeControl("Headphone volume", monitorVolume));
        var routes = new TableLayoutPanel { AutoSize = true, ColumnCount = 2, Dock = DockStyle.Top, Margin = Padding.Empty };
        routes.ColumnStyles.Add(new(SizeType.Percent, 50)); routes.ColumnStyles.Add(new(SizeType.Percent, 50));
        soundCard.Dock = headphoneCard.Dock = DockStyle.Fill;
        soundCard.Margin = new(0, 12, 8, 8); headphoneCard.Margin = new(8, 12, 0, 8);
        routes.Controls.Add(soundCard, 0, 0); routes.Controls.Add(headphoneCard, 1, 0);
        Add(content, routes);
        var saved = Body("Changes take effect when you apply. Stop playing sounds before switching outputs.");
        var apply = Button("Apply audio settings", () =>
        {
            if (outputs.SelectedItem is not DeviceInfo device) return;
            if (monitorOutputs.SelectedItem is not DeviceInfo monitor) return;
            var devices = audio.Devices();
            lock (store.Gate)
            {
                store.Save(AudioRouting.Apply(store.State, new(device.Id, volume.Value / 100f, monitorEnabled.Checked, monitor.Id, monitorVolume.Value / 100f), devices));
                audio.SetVolume(store.State.Volume); audio.SetMonitorVolume(store.State.MonitorVolume);
            }
            saved.Text = "Audio settings saved. Test a sound to hear your setup.";
            AddLog("Audio settings saved: " + device.Name);
        }, primary: true);
        var test = Button("Test sound", () => { lock (store.Gate) { var clip = store.State.Clips.FirstOrDefault(); if (clip is not null) audio.Play(store.ClipPath(clip.Id), store.State.OutputId, monitorOutputId: store.State.MonitorEnabled ? store.State.MonitorOutputId : null, monitorVolume: store.State.MonitorVolume); } });
        Add(content, Actions(apply, test, Button("Refresh devices", RefreshOutputs)), saved);
        Add(content, Disclosure("Set up game voice chat", Body("1. Install VB-CABLE, choose CABLE Input above, and apply.\n\n2. Choose CABLE Output as the microphone in your game or Discord. Open its microphone test and play a test sound.\n\n3. Use voice activation or hold your physical push-to-talk key while the clip plays.\n\n4. If clips are cut off, lower the voice threshold and disable noise suppression."),
            Body("Use only one headphone monitoring route. If you already listen through Windows or Voicemeeter, leave Hear sounds myself off to avoid an echo."),
            Actions(Button("Get VB-CABLE", () => System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo("https://vb-audio.com/Cable/") { UseShellExecute = true })))));
        var importButton = Button("Import sounds from PC", () => { });
        importButton.Click += async (_, _) => await ImportSounds(importButton);
        Add(content, Card("More sounds. More personality.", Body("Bring your own audio into Riff. Choose multiple files, up to 60 seconds and 20 MB each."), Actions(importButton)));
        return page;
    }
    async Task ImportSounds(Button button)
    {
        using var dialog = new OpenFileDialog
        {
            Filter = "Audio files|*.wav;*.mp3;*.m4a;*.aac;*.aiff;*.aif",
            Title = "Import sounds (up to 60 seconds and 20 MB each)",
            Multiselect = true
        };
        if (dialog.ShowDialog(this) != DialogResult.OK) return;
        button.Enabled = false;
        var imported = 0;
        var failures = new List<string>();
        try
        {
            foreach (var path in dialog.FileNames)
            {
                if (IsDisposed || Disposing || stopping) break;
                button.Text = $"Importing {imported + failures.Count + 1} of {dialog.FileNames.Length}…";
                try
                {
                    var clip = await Task.Run(() =>
                    {
                        if (new FileInfo(path).Length > 20 * 1024 * 1024)
                            throw new ArgumentException("Choose a file smaller than 20 MB.");
                        var name = Path.GetFileNameWithoutExtension(path).Trim();
                        if (name.Length > 60)
                            name = name[..(char.IsHighSurrogate(name[59]) ? 59 : 60)];
                        return AudioEngine.Import(path, string.IsNullOrWhiteSpace(name) ? "Imported sound" : name, store);
                    });
                    imported++;
                    AddLog("Imported: " + clip.Name);
                }
                catch (Exception ex)
                {
                    var failure = Path.GetFileName(path) + ": " + ex.Message;
                    failures.Add(failure);
                    AddLog("Import failed: " + failure);
                }
            }
            if (!IsDisposed && !Disposing && !stopping)
            {
                var summary = $"Imported {imported} of {dialog.FileNames.Length} sounds.";
                if (failures.Count > 0)
                    summary += "\n\n" + string.Join("\n", failures.Take(10))
                        + (failures.Count > 10 ? "\nSee the log for the remaining errors." : "");
                MessageBox.Show(this, summary, "Import sounds", MessageBoxButtons.OK,
                    failures.Count > 0 ? MessageBoxIcon.Warning : MessageBoxIcon.Information);
            }
        }
        finally
        {
            if (!button.IsDisposed) { button.Text = "Import sounds from PC"; button.Enabled = true; }
        }
    }
    Panel ControlsPage()
    {
        var page = Page("Controls", "Play your way.", "Choose what your iPad can do on this PC.", out var content);
        var soundboard = new CheckBox { Text = "Soundboard mode", AutoSize = true, Checked = store.State.SoundboardOnly, Font = StrongFont, Margin = new(0, 0, 0, 12) };
        soundboard.CheckedChanged += (_, _) =>
        {
            try
            {
                runner.SetSoundboardOnly(soundboard.Checked);
                AddLog(soundboard.Checked ? "Soundboard mode on. Desktop automation is blocked." : "Desktop automation enabled. Use Soundboard mode before playing a game.");
            }
            catch (Exception ex)
            {
                soundboard.Checked = store.State.SoundboardOnly;
                AddLog(ex.Message); MessageBox.Show(this, ex.Message, "Could not change controls");
            }
        };
        Add(content, Card("Just sounds while you play", soundboard,
            Body("Recommended for games. Sounds, recording, imports, volume, and Stop all stay available. Keyboard shortcuts, typed text, media keys, app and website launches, and sequences are blocked."),
            Body("Turn this off here when you want desktop shortcuts. The iPad cannot change this setting. Changing modes cancels pending sequence steps; your choice is saved.")));
        var aiStatus = Body(server.AI.Enabled ? "AI suggestions are enabled." : "Add your OpenAI API key to enable suggestions.");
        var key = new TextBox { UseSystemPasswordChar = true, PlaceholderText = "OpenAI API key", AccessibleName = "OpenAI API key" };
        Add(content, Card("AI button suggestions", Body("Get suggested names, icons, colors, and starter decks with GPT-5.6 Luna. Review every suggestion on your iPad before using it."),
            Body("Suggestions send game/app and sound names, descriptions, existing button names, and action details (including typed text) to OpenAI. Audio files and app paths stay on your devices. OpenAI API usage is billed to your account."),
            aiStatus, Label("OpenAI API key", StrongFont), Field(key), Actions(
                Button("Enable suggestions", () => { server.AI.Save(key.Text); key.Clear(); aiStatus.Text = "AI suggestions are enabled."; }, primary: true),
                Button("Disable & remove key", () => { server.AI.Disable(); key.Clear(); aiStatus.Text = "AI suggestions are disabled. Your API key was removed."; })),
            Body("Your key is encrypted for your Windows account and never sent to the iPad. You can edit suggestions or turn them off while adding a button.")));
        Add(content, Disclosure("Built to stay outside the game", Body("Riff does not inject code, inspect game memory, install hooks, or modify game files. Steam deck switching reads only local library files and running-game registry flags. For voice chat, use a virtual audio device and hold your physical push-to-talk key yourself, or use voice activation where allowed."),
            Body("Soundboard mode reduces automation risk; it is not anti-cheat approval. Follow your game’s rules for third-party audio and voice chat. Never bypass anti-cheat blocks or enable automation to gain a gameplay advantage.")));
        return page;
    }
    Panel AppsPage()
    {
        var page = Page("Allowed apps", "Your shortcuts. Your rules.", "Make your favorite PC apps a tap away.", out var content);
        apps.DrawMode = DrawMode.OwnerDrawFixed;
        apps.ItemHeight = 64;
        apps.DrawItem += (_, args) =>
        {
            if (args.Index < 0 || apps.Items[args.Index] is not LaunchTarget target) return;
            var selected = (args.State & DrawItemState.Selected) != 0;
            var background = selected ? Inset : Surface;
            var foreground = Ink;
            if (SystemInformation.HighContrast) { background = selected ? SystemColors.Highlight : SystemColors.Window; foreground = selected ? SystemColors.HighlightText : SystemColors.WindowText; }
            using var brush = new SolidBrush(background); args.Graphics.FillRectangle(brush, args.Bounds);
            var inset = 12 * apps.DeviceDpi / 96;
            var bounds = Rectangle.Inflate(args.Bounds, -inset, 0); bounds.Y += inset / 2; bounds.Height = args.Bounds.Height / 2;
            TextRenderer.DrawText(args.Graphics, target.Name, StrongFont, bounds, foreground, TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix);
            bounds.Y += args.Bounds.Height / 2 - inset / 2;
            TextRenderer.DrawText(args.Graphics, target.Path, BodyFont, bounds, SystemInformation.HighContrast ? foreground : Muted, TextFormatFlags.Left | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix);
            args.DrawFocusRectangle();
        };
        apps.DpiChangedAfterParent += (_, _) => apps.ItemHeight = 64 * apps.DeviceDpi / 96;
        var remove = Button("Remove selected", () => { if (apps.SelectedItem is LaunchTarget target) { store.RemoveApp(target.Id); RefreshApps(); } });
        apps.SelectedIndexChanged += (_, _) => remove.Enabled = apps.SelectedItem is LaunchTarget;
        var add = Button("Add application", () =>
        {
            using var dialog = new OpenFileDialog { Filter = "Windows applications|*.exe", Title = "Allow an application" };
            if (dialog.ShowDialog(this) == DialogResult.OK) { store.AddApp(dialog.FileName); RefreshApps(); }
        }, primary: true);
        Add(content, Card("Ready to launch", Body("Add a Windows application, then choose Launch app when creating a button on your iPad."), emptyApps, apps, Actions(add, remove)));
        Add(content, Card("The rest happens on your iPad", Body("Configure keyboard shortcuts, typed text, websites, media controls, and multi-step sequences in Riff on your iPad. Shortcuts go to the focused Windows app. Riff does not accept shell commands from your iPad."),
            Body("Steam game detection is automatic while Steam is running. Link a game to a deck on your iPad. No Steam login or API key is needed.")));
        RefreshApps(); remove.Enabled = apps.SelectedItem is LaunchTarget; return page;
    }
    Panel ActivityPage()
    {
        var page = Page("Activity", "Behind the sounds.", "Connection events and useful details when something needs attention.", out var content);
        log.Height = 380;
        var clear = Button("Clear activity", log.Clear);
        Add(content, Card("Recent activity", log, Actions(clear)), Body("Activity is shown for this session. Closing the window keeps Riff running in your system tray."));
        return page;
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
        var devices = audio.Devices();
        var primaryDevices = devices.ToList();
        if (!primaryDevices.Any(d => d.Id == store.State.OutputId)) primaryDevices.Add(new(store.State.OutputId, "Disconnected output"));
        outputs.DataSource = primaryDevices; outputs.SelectedValue = store.State.OutputId;
        var headphoneDevices = devices.ToList();
        if (!headphoneDevices.Any(d => d.Id == store.State.MonitorOutputId)) headphoneDevices.Add(new(store.State.MonitorOutputId, "Disconnected headphones"));
        monitorOutputs.DataSource = headphoneDevices; monitorOutputs.SelectedValue = store.State.MonitorOutputId;
        if (outputs.SelectedIndex < 0) { outputs.SelectedIndex = 0; AddLog("Saved audio output is disconnected. Choose and apply another output."); }
    }
    void RefreshApps()
    {
        lock (store.Gate) apps.DataSource = store.State.Apps.ToList();
        emptyApps.Visible = apps.Items.Count == 0;
        apps.Visible = apps.Items.Count > 0;
    }
    static Label Body(string text) => Label(text, color: Muted);
    static TableLayoutPanel VolumeControl(string title, TrackBar slider)
    {
        var stack = Stack();
        var value = Label($"{title}   {slider.Value}%", StrongFont);
        slider.ValueChanged += (_, _) => value.Text = $"{title}   {slider.Value}%";
        Add(stack, value, slider); return stack;
    }
    static RoundedCard Disclosure(string title, params Control[] children)
    {
        var card = new RoundedCard { Padding = new(24, 16, 24, 6) };
        var toggle = new CheckBox { Text = title, UseMnemonic = false, AutoSize = true, Font = StrongFont, Margin = new(0, 0, 0, 10) };
        var details = Stack(); Add(details, children); details.Visible = false;
        toggle.CheckedChanged += (_, _) => details.Visible = toggle.Checked;
        Add(card, toggle, details); return card;
    }
    RiffButton Button(string text, Action action, bool primary = false)
    {
        var button = new RiffButton(text) { Primary = primary };
        button.Click += (_, _) => { try { action(); } catch (Exception ex) { AddLog(ex.Message); MessageBox.Show(this, ex.Message, "Riff needs attention"); } }; return button;
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
        if (!Enabled) return;
        Enabled = false; timer.Stop();
        try { await server.Stop(); }
        catch (Exception error) { AddLog("Could not finish cleanup: " + error.Message); }
        finally { stopping = true; Close(); }
    }
    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            server.Activity -= AddLog;
            audio.Warning -= AddLog;
            tray?.Dispose(); timer.Dispose();
            var image = qr.Image; qr.Image = null; image?.Dispose();
        }
        base.Dispose(disposing);
    }
}
