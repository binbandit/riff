using Riff.Core;
using Xunit;

namespace Riff.WindowsTests;

public class ReleaseNotesTests
{
    [Fact]
    public async Task NativeRichTextControlAcceptsMarkdownAndPreservesVisibleFormatting()
    {
        var completion = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var thread = new Thread(() =>
        {
            try
            {
                using var view = new RichTextBox();
                view.Rtf = ReleaseMarkdown.ToRtf("""
                    <!-- hidden -->
                    # Latest release
                    A **bold** sound and *quiet* controls. Ready ☑
                    - First
                      - Nested
                    [Read more](https://github.com/binbandit/riff/releases)
                    ```text
                    {literal code}
                    ```
                    | Button | Result |
                    | --- | --- |
                    | Tap | Play |
                    """, CompanionRelease.ReleasesPage);
                Assert.Contains("Latest release", view.Text);
                Assert.Contains("Nested", view.Text);
                Assert.Contains("Ready ☑", view.Text);
                Assert.Contains("{literal code}", view.Text);
                Assert.Contains("Result", view.Text);
                Assert.DoesNotContain("hidden", view.Text);
                Assert.DoesNotContain("**", view.Text);
                view.Select(view.Text.IndexOf("bold", StringComparison.Ordinal), 4);
                Assert.True(view.SelectionFont!.Bold);
                view.Select(view.Text.IndexOf("quiet", StringComparison.Ordinal), 5);
                Assert.True(view.SelectionFont!.Italic);
                completion.SetResult();
            }
            catch (Exception error) { completion.SetException(error); }
        }) { IsBackground = true };
        thread.SetApartmentState(ApartmentState.STA); thread.Start();
        await completion.Task.WaitAsync(TimeSpan.FromSeconds(30));
    }
}
