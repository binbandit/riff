using System.Net;
using Riff.Companion;
using Xunit;

namespace Riff.WindowsTests;

public class UpdateErrorTests
{
    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public async Task InvalidReleaseOrMissingChangelogStaysInlineAndCanBeRetried(bool hasDownload)
    {
        var completion = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var thread = new Thread(() =>
        {
            try
            {
                var handler = new ReleaseFixture(hasDownload);
                using var view = new CompanionUpdatesView(handler);
                // The completed fixture runs synchronously, so no Windows message loop is needed.
                view.Check(force: true).GetAwaiter().GetResult();
                if (hasDownload)
                    Assert.Contains("does not include a CHANGELOG.md", Assert.Single(Descendants(view).OfType<RichTextBox>()).Text);
                else
                    Assert.Contains(Descendants(view).OfType<Label>(), label => label.Text.Contains("Windows downloads are not ready"));
                Assert.True(Assert.Single(Descendants(view).OfType<Button>(), button => button.Text == "Check for updates").Enabled);
                view.Check(force: true).GetAwaiter().GetResult();
                Assert.Equal(2, handler.Requests);
                view.Dispose();
                view.Dispose();
                completion.SetResult();
            }
            catch (Exception error) { completion.SetException(error); }
        }) { IsBackground = true };
        thread.SetApartmentState(ApartmentState.STA); thread.Start();
        await completion.Task.WaitAsync(TimeSpan.FromSeconds(30));
    }
    sealed class ReleaseFixture(bool hasDownload) : HttpMessageHandler
    {
        public int Requests { get; private set; }
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            Requests++;
            var assets = hasDownload ? """[{"id":1,"name":"Riff-9.0.0-win-x64.zip","state":"uploaded","size":100}]""" : "[]";
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent("""[{"tag_name":"companion-v9.0.0","draft":false,"prerelease":false,"assets":ASSETS}]""".Replace("ASSETS", assets))
            });
        }
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
