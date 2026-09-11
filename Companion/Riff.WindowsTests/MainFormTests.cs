using Riff.Companion;
using Riff.Core;
using Xunit;

namespace Riff.WindowsTests;

public class MainFormTests
{
    [Theory]
    [InlineData("")]
    [InlineData("disconnected-output")]
    public async Task StartupSelectsDefaultOutputWhenSavedOutputIsDefaultOrDisconnected(string outputId)
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

                    var output = Assert.Single(Descendants(form).OfType<ComboBox>(), control => control.ValueMember == "Id");
                    Assert.Equal("", Assert.IsType<DeviceInfo>(output.SelectedItem).Id);
                    Assert.Equal("PC default output", output.Text);
                    Assert.Equal(outputId, store.State.OutputId);
                    var activity = Assert.Single(Descendants(form).OfType<TabPage>(), page => page.Text == "Activity");
                    Assert.Equal(outputId.Length > 0, activity.Controls.OfType<TextBox>().Single().Text.Contains("disconnected"));
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

    static IEnumerable<Control> Descendants(Control parent)
    {
        foreach (Control control in parent.Controls)
        {
            yield return control;
            foreach (var child in Descendants(control)) yield return child;
        }
    }
}
