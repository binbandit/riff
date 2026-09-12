using Riff.Companion;
using Riff.Core;
using Xunit;

namespace Riff.Tests;

public class AppearanceTests
{
    [Theory]
    [InlineData(null, null)]
    [InlineData("future-theme", "dark")]
    [InlineData("warm", "system")]
    [InlineData("ocean", null)]
    public void MissingOrUnknownHeadersDoNotReplaceAppearance(string? theme, string? mode)
        => Assert.Null(CompanionAppearance.Parse(theme, mode));

    [Fact]
    public void AppearanceSurvivesRestartAndMalformedFilesFallBack()
    {
        var folder = Path.Combine(Path.GetTempPath(), "riff-appearance-" + Guid.NewGuid());
        Directory.CreateDirectory(folder);
        try
        {
            var preferences = new AppearancePreferences(folder);
            Assert.Equal(new CompanionAppearance(), preferences.Current);
            preferences.Update(CompanionAppearance.Parse("ocean", "dark")!);
            Assert.Equal(new CompanionAppearance("ocean", true), new AppearancePreferences(folder).Current);
            Assert.Equal(0x111C22, preferences.Current.Palette.Canvas);
            preferences.Update(CompanionAppearance.Parse("amoled", "light")!);
            Assert.True(new AppearancePreferences(folder).Current.Dark);
            Assert.Equal(0, preferences.Current.Palette.Surface);
            File.WriteAllText(Path.Combine(folder, "appearance.json"), "{broken");
            Assert.Equal(new CompanionAppearance(), new AppearancePreferences(folder).Current);
            File.WriteAllText(Path.Combine(folder, "appearance.json"), "{\"Theme\":\"future-theme\",\"Dark\":true}");
            Assert.Equal(new CompanionAppearance(), new AppearancePreferences(folder).Current);
        }
        finally { Directory.Delete(folder, true); }
    }

    [Fact]
    public void ReleaseNotesUseThemeColorsWithoutLosingFormatting()
    {
        var colors = AppTheme.All["ocean"].Dark;
        var rtf = ReleaseMarkdown.ToRtf("**Hello** `code`", new Uri("https://github.com/binbandit/riff"),
            0xF5F3F0, colors.Accent, colors.Inset, 0xB0B0B0);
        Assert.Contains(@"\red245\green243\blue240;", rtf);
        Assert.Contains(@"\red117\green207\blue222;", rtf);
        Assert.Contains(@"\red42\green65\blue76;", rtf);
        Assert.Contains(@"\b ", rtf);
        Assert.Contains(@"\highlight3 ", rtf);
    }
}
