using Riff.Companion;
using Riff.Core;
using Xunit;

namespace Riff.WindowsTests;

public class MainFormTests
{
    [Theory]
    [InlineData("")]
    [InlineData("disconnected-output")]
    public async Task StartupPreservesSavedOutputAndBindsHeadphonesIndependently(string outputId)
    {
        var completion = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var thread = new Thread(() =>
        {
            var folder = Path.Combine(Path.GetTempPath(), "riff-ui-test-" + Guid.NewGuid().ToString("N"));
            try
            {
                try
                {
                    var store = new StateStore(folder);
                    store.Save(store.State with { OutputId = outputId });
                    using var identity = new PairingIdentity(folder);
                    using var audio = new AudioEngine();
                    using var runner = new ActionRunner(store, audio);
                    var server = new CompanionServer(store, identity, audio, runner);
                    using var form = new MainForm(store, identity, audio, runner, server);

                    var output = Assert.Single(Descendants(form).OfType<ComboBox>(), control => control.AccessibleName == "Sound output");
                    Assert.Equal(outputId, Assert.IsType<DeviceInfo>(output.SelectedItem).Id);
                    Assert.Equal(outputId.Length == 0 ? "PC default output" : "Disconnected output", output.Text);
                    var headphones = Assert.Single(Descendants(form).OfType<ComboBox>(), control => control.AccessibleName == "Headphone output");
                    Assert.Equal("", Assert.IsType<DeviceInfo>(headphones.SelectedItem).Id);
                    Assert.Equal(outputId, store.State.OutputId);
                }
                finally
                {
                    if (Directory.Exists(folder)) Directory.Delete(folder, true);
                }
                completion.SetResult();
            }
            catch (Exception error) { completion.SetException(error); }
        }) { IsBackground = true };
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
        await completion.Task.WaitAsync(TimeSpan.FromSeconds(30));
    }

    [Theory]
    [InlineData(960, 720)]
    [InlineData(1100, 820)]
    public async Task PagesFitWindowAndRetainAudioDraftWhenNavigating(int width, int height)
    {
        var completion = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var thread = new Thread(() =>
        {
            var folder = Path.Combine(Path.GetTempPath(), "riff-layout-test-" + Guid.NewGuid().ToString("N"));
            try
            {
                try
                {
                    var store = new StateStore(folder);
                    using var identity = new PairingIdentity(folder);
                    using var audio = new AudioEngine();
                    using var runner = new ActionRunner(store, audio);
                    var server = new CompanionServer(store, identity, audio, runner);
                    using var form = new MainForm(store, identity, audio, runner, server);
                    // Host the real control tree without starting the server or the startup update check.
                    using var host = new Form { ClientSize = new(width, height), Font = form.Font };
                    host.Controls.Add(form.Controls[0]);
                    host.Show(); Application.DoEvents();
                    var controls = Descendants(host).ToArray();
                    foreach (var title in new[] { "Connect iPad", "Audio & voice chat", "Controls", "Allowed apps", "Updates", "Activity" })
                    {
                        var button = Assert.Single(controls.OfType<Button>(), b => b.Text == title);
                        button.PerformClick(); Application.DoEvents();
                        Assert.Equal("Current page", button.AccessibleDescription);
                        var page = Assert.Single(controls, c => c.Name == title);
                        Assert.True(page.Visible);
                        Assert.Single(page.Parent!.Controls.Cast<Control>(), c => c.Visible);
                        foreach (var scroll in Descendants(page).Prepend(page).OfType<ScrollableControl>().Where(c => c.Visible && c.AutoScroll))
                            Assert.False(scroll.HorizontalScroll.Visible, $"{title} has horizontal scrolling at {width} x {height}");
                        foreach (var control in Descendants(page).Where(c => c.Visible))
                            Assert.True(control.Left >= 0 && control.Right <= control.Parent!.ClientSize.Width,
                                $"{title}: {control.GetType().Name} '{control.Text}' exceeds its container at {width} x {height}");
                        Assert.True(Assert.Single(controls.OfType<Button>(), b => b.Text == "Stop all sounds").Visible);
                    }
                    var audioButton = controls.OfType<Button>().Single(b => b.Text == "Audio & voice chat");
                    audioButton.PerformClick();
                    var volume = controls.OfType<TrackBar>().Single(c => c.AccessibleName == "Sound volume");
                    volume.Value = 37;
                    controls.OfType<Button>().Single(b => b.Text == "Connect iPad").PerformClick();
                    audioButton.PerformClick();
                    Assert.Equal(37, volume.Value);
                    Assert.Contains(controls.OfType<Label>(), label => label.Text == "Sound volume   37%");
                    Assert.NotEqual(0.37f, store.State.Volume);
                    host.Close();
                }
                finally { if (Directory.Exists(folder)) Directory.Delete(folder, true); }
                completion.SetResult();
            }
            catch (Exception error) { completion.SetException(error); }
        }) { IsBackground = true };
        thread.SetApartmentState(ApartmentState.STA); thread.Start();
        await completion.Task.WaitAsync(TimeSpan.FromSeconds(30));
    }

    static IEnumerable<Control> Descendants(Control parent)
    {
        foreach (Control control in parent.Controls)
        {
            yield return control;
            foreach (var child in Descendants(control)) yield return child;
        }
    }
}
