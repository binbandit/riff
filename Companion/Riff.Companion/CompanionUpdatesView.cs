using System.Diagnostics;
using Riff.Core;
using static Riff.Companion.CompanionTheme;

namespace Riff.Companion;

public sealed class CompanionUpdatesView : UserControl
{
    readonly HttpClient http;
    readonly CancellationTokenSource lifetime = new();
    readonly Label versions = Label("", SectionFont);
    readonly Label state = Label("Checking GitHub for the latest Windows release…", color: Muted);
    readonly Button check = new RiffButton("Check for updates") { Primary = true };
    readonly Button download = new RiffButton("Open downloads on GitHub");
    readonly RichTextBox notes = new() { Height = 360, ReadOnly = true, BorderStyle = BorderStyle.None, BackColor = Surface, ForeColor = Ink, Font = BodyFont, DetectUrls = true, ScrollBars = RichTextBoxScrollBars.Vertical, AccessibleName = "Latest companion release notes" };
    readonly Label notesHeading = Label("What’s new", SectionFont);
    readonly System.Windows.Forms.Timer timer = new() { Interval = 60 * 60 * 1000 };
    CompanionRelease? release;
    DateTime nextCheck;
    bool checking;
    public event Action<bool>? UpdateAvailable;

    public CompanionUpdatesView(HttpMessageHandler? updateHandler = null)
    {
        http = new HttpClient(updateHandler ?? new HttpClientHandler { UseCookies = false });
        AutoScaleDimensions = new(96, 96); AutoScaleMode = AutoScaleMode.Dpi;
        Dock = DockStyle.Fill; BackColor = Canvas; ForeColor = Ink; Font = BodyFont;
        Name = "Updates"; AccessibleName = "Updates";
        var page = Page("Companion updates", "Keep your companion in tune.", "The latest improvements, all in one place.", out var content);
        versions.Text = $"Installed {CompanionBuild.Version}";
        var current = new RoundedCard();
        Add(current, versions, state, Actions(check, download)); Add(content, current);
        check.Click += async (_, _) => await Check(force: true);
        download.Click += (_, _) => Open(release?.Page ?? CompanionRelease.ReleasesPage);
        notes.LinkClicked += (_, args) => { if (ReleaseMarkdown.ClickedLink(args.LinkText) is { } url) Open(url); };
        var releaseNotes = new RoundedCard();
        Add(releaseNotes, notesHeading, notes); Add(content, releaseNotes);
        Add(content, Label("Updates are checked automatically. Downloads open on GitHub, and you choose when to install. Your decks and clips stay on this PC.", color: Muted));
        var license = new LinkLabel { Text = "Markdown renderer license", AutoSize = true, LinkColor = Accent, ActiveLinkColor = Accent, VisitedLinkColor = Muted, Margin = new(0, 8, 0, 0) };
        license.LinkClicked += (_, _) => ShowLicense(); Add(content, license);
        Controls.Add(page);
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
            catch (Exception ex) when (ex is HttpRequestException or IOException or InvalidDataException or System.Text.Json.JsonException or OperationCanceledException or System.Text.DecoderFallbackException)
            {
                if (!lifetime.IsCancellationRequested) notes.Text = ex is OperationCanceledException ? "The release notes took too long to load. Check again, or open the release on GitHub." : ex.Message;
            }
        }
        catch (Exception ex) when (ex is HttpRequestException or IOException or InvalidDataException or System.Text.Json.JsonException or OperationCanceledException)
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
        using var dialog = new Form { Text = "Markdown renderer license", Size = new(650, 550), StartPosition = FormStartPosition.CenterParent, BackColor = Canvas, ForeColor = Ink, Padding = new(24) };
        var text = new TextBox { Dock = DockStyle.Fill, Multiline = true, ReadOnly = true, ScrollBars = ScrollBars.Vertical, Font = BodyFont, BackColor = Surface, ForeColor = Ink, BorderStyle = BorderStyle.None };
        try { text.Text = File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "Markdig-LICENSE.txt")).Replace("\n", Environment.NewLine); }
        catch (IOException) { text.Text = "Markdig · BSD 2-Clause license\r\nhttps://github.com/xoofx/markdig"; }
        dialog.Controls.Add(text); dialog.ShowDialog(this);
    }
    protected override void Dispose(bool disposing)
    {
        if (disposing && !IsDisposed) { lifetime.Cancel(); timer.Dispose(); http.Dispose(); lifetime.Dispose(); }
        base.Dispose(disposing);
    }
}
