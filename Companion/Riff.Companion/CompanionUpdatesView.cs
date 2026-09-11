using System.Diagnostics;
using Riff.Core;

namespace Riff.Companion;

public sealed class CompanionUpdatesView : UserControl
{
    readonly HttpClient http = new(new HttpClientHandler { UseCookies = false });
    readonly CancellationTokenSource lifetime = new();
    readonly Label heading = new() { AutoSize = true, Text = "Keep your companion in tune.", Font = new("Segoe UI", 22, FontStyle.Bold), Margin = new(0, 0, 0, 10) };
    readonly Label versions = new() { AutoSize = true, ForeColor = Color.Silver, Margin = new(0, 0, 0, 12) };
    readonly Label state = new() { AutoSize = true, Text = "Checking GitHub for the latest Windows release…", MaximumSize = new(740, 0), Margin = new(0, 0, 0, 12) };
    readonly Button check = MakeButton("Check for updates");
    readonly Button download = MakeButton("Open downloads on GitHub");
    readonly RichTextBox notes = new() { Dock = DockStyle.Fill, ReadOnly = true, BorderStyle = BorderStyle.None, BackColor = Color.FromArgb(24, 28, 34), ForeColor = Color.FromArgb(238, 240, 243), Font = new("Segoe UI", 11), DetectUrls = true, ScrollBars = RichTextBoxScrollBars.Vertical, AccessibleName = "Latest companion release notes" };
    readonly Label notesHeading = new() { AutoSize = true, Text = "What’s new", Font = new("Segoe UI", 16, FontStyle.Bold), Margin = new(0, 10, 0, 10) };
    readonly System.Windows.Forms.Timer timer = new() { Interval = 60 * 60 * 1000 };
    CompanionRelease? release;
    DateTime nextCheck;
    bool checking;
    public event Action<bool>? UpdateAvailable;

    public CompanionUpdatesView()
    {
        Dock = DockStyle.Fill; BackColor = Color.FromArgb(24, 28, 34); ForeColor = Color.White;
        var layout = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 1, RowCount = 4, Padding = new(24) };
        layout.ColumnStyles.Add(new(SizeType.Percent, 100));
        layout.RowStyles.Add(new(SizeType.AutoSize)); layout.RowStyles.Add(new(SizeType.AutoSize));
        layout.RowStyles.Add(new(SizeType.Percent, 100)); layout.RowStyles.Add(new(SizeType.AutoSize));
        var top = new FlowLayoutPanel { AutoSize = true, Dock = DockStyle.Fill, FlowDirection = FlowDirection.TopDown, WrapContents = false };
        versions.Text = $"Installed {CompanionBuild.Version}";
        top.Controls.AddRange([heading, versions, state]);
        var buttons = new FlowLayoutPanel { AutoSize = true, Dock = DockStyle.Top, WrapContents = true };
        buttons.Controls.AddRange([check, download]); top.Controls.Add(buttons);
        check.Click += async (_, _) => await Check(force: true);
        download.Click += (_, _) => Open(release?.Page ?? CompanionRelease.ReleasesPage);
        notes.LinkClicked += (_, args) => { if (ReleaseMarkdown.ClickedLink(args.LinkText) is { } url) Open(url); };
        layout.Controls.Add(top, 0, 0); layout.Controls.Add(notesHeading, 0, 1); layout.Controls.Add(notes, 0, 2);
        var footer = new FlowLayoutPanel { AutoSize = true, Dock = DockStyle.Fill, FlowDirection = FlowDirection.TopDown, WrapContents = false, Padding = new(0, 12, 0, 0) };
        footer.Controls.Add(new Label { Text = "Updates are checked automatically. Downloads open on GitHub, and you choose when to install. Your decks and clips stay on this PC.", AutoSize = true, MaximumSize = new(720, 0), ForeColor = Color.Silver });
        var license = new LinkLabel { Text = "Markdown renderer license", AutoSize = true, LinkColor = Color.FromArgb(255, 156, 105), Margin = new(0, 8, 0, 0) };
        license.LinkClicked += (_, _) => ShowLicense(); footer.Controls.Add(license);
        layout.Controls.Add(footer, 0, 3); Controls.Add(layout);
        timer.Tick += async (_, _) => await Check(); timer.Start();
    }
    public async Task Check(bool force = false)
    {
        if (checking || lifetime.IsCancellationRequested || (!force && DateTime.UtcNow < nextCheck)) return;
        checking = true; check.Enabled = false; state.Text = "Checking GitHub…";
        try
        {
            var client = new CompanionReleaseClient(http);
            var latest = await client.Fetch(lifetime.Token);
            if (lifetime.IsCancellationRequested) return;
            nextCheck = DateTime.UtcNow.AddHours(6);
            release = latest;
            if (latest is null)
            {
                versions.Text = $"Installed {CompanionBuild.Version}";
                state.Text = "No stable Windows release has been published yet."; notes.Clear();
                UpdateAvailable?.Invoke(false); return;
            }
            var current = CompanionVersion.Parse(CompanionBuild.Version);
            var newer = current is not null && latest.Version!.CompareTo(current) > 0;
            versions.Text = $"Installed {CompanionBuild.Version}   ·   Latest {latest.Version!.Value}";
            state.Text = current is null ? "The installed version could not be compared. Check the latest release on GitHub."
                : newer ? "An update is ready. Open GitHub to download the latest companion."
                : latest.Version.CompareTo(current) == 0 ? "You’re up to date." : "You’re running a build ahead of the latest stable release.";
            UpdateAvailable?.Invoke(newer);
            notesHeading.Text = $"What’s new in {latest.Version.Value}";
            notes.Text = "Loading release notes…";
            try
            {
                var markdown = await client.FetchChangelog(latest, lifetime.Token);
                if (lifetime.IsCancellationRequested) return;
                notes.Rtf = ReleaseMarkdown.ToRtf(markdown, latest.Page);
                notes.Select(0, 0); notes.ScrollToCaret();
            }
            catch (Exception ex) when (ex is HttpRequestException or IOException or System.Text.Json.JsonException or OperationCanceledException or System.Text.DecoderFallbackException)
            {
                if (!lifetime.IsCancellationRequested) notes.Text = ex is OperationCanceledException ? "The release notes took too long to load. Check again, or open the release on GitHub." : ex.Message;
            }
        }
        catch (Exception ex) when (ex is HttpRequestException or IOException or System.Text.Json.JsonException or OperationCanceledException)
        {
            if (!lifetime.IsCancellationRequested)
            {
                nextCheck = DateTime.UtcNow.AddMinutes(15);
                state.Text = ex is OperationCanceledException ? "The check took too long. Check your connection and try again." : ex.Message;
            }
        }
        finally { checking = false; if (!IsDisposed) check.Enabled = true; }
    }
    void Open(Uri url)
    {
        try { Process.Start(new ProcessStartInfo(url.AbsoluteUri) { UseShellExecute = true }); }
        catch (Exception ex) { MessageBox.Show(this, ex.Message, "Could not open GitHub"); }
    }
    void ShowLicense()
    {
        using var dialog = new Form { Text = "Markdown renderer license", Size = new(650, 550), StartPosition = FormStartPosition.CenterParent };
        var text = new TextBox { Dock = DockStyle.Fill, Multiline = true, ReadOnly = true, ScrollBars = ScrollBars.Vertical, Font = new("Segoe UI", 10) };
        try { text.Text = File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "Markdig-LICENSE.txt")).Replace("\n", Environment.NewLine); }
        catch (IOException) { text.Text = "Markdig · BSD 2-Clause license\r\nhttps://github.com/xoofx/markdig"; }
        dialog.Controls.Add(text); dialog.ShowDialog(this);
    }
    static Button MakeButton(string title)
    {
        var button = new Button { Text = title, AutoSize = true, FlatStyle = FlatStyle.Flat, Padding = new(12, 7, 12, 7), Margin = new(0, 0, 10, 10), BackColor = Color.FromArgb(255, 140, 79), ForeColor = Color.FromArgb(14, 16, 20) };
        button.FlatAppearance.BorderSize = 0; return button;
    }
    protected override void Dispose(bool disposing)
    {
        if (disposing) { lifetime.Cancel(); timer.Dispose(); http.Dispose(); lifetime.Dispose(); }
        base.Dispose(disposing);
    }
}
