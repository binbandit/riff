namespace Riff.Core;

public sealed record ThemePalette(int Canvas, int Surface, int Inset, int Accent);
public sealed record AppTheme(ThemePalette Light, ThemePalette Dark)
{
    // Keep these values aligned with Riff/Design/Theme.swift.
    public static IReadOnlyDictionary<string, AppTheme> All { get; } = new Dictionary<string, AppTheme>
    {
        ["warm"] = new(new(0xF6F3EE, 0xFFFFFF, 0xEAE6DF, 0xBA382F), new(0x191918, 0x272725, 0x343431, 0xFF968B)),
        ["ocean"] = new(new(0xECF3F5, 0xF9FDFE, 0xDCE9EE, 0x00677C), new(0x111C22, 0x1E3039, 0x2A414C, 0x75CFDE)),
        ["orchid"] = new(new(0xF5EFF7, 0xFEFBFF, 0xEADFEF, 0x81509B), new(0x201922, 0x322737, 0x44364A, 0xD5AFF0)),
        ["graphite"] = new(new(0xF0F1F3, 0xFFFFFF, 0xE1E3E7, 0x425D8A), new(0x15171B, 0x25282E, 0x343940, 0xA8BFE7)),
        ["amoled"] = new(new(0x000000, 0x000000, 0x121212, 0xA8BFE7), new(0x000000, 0x000000, 0x121212, 0xA8BFE7)),
        ["forest"] = new(new(0xEEF3EB, 0xFAFCF7, 0xDDE7D7, 0x326344), new(0x111D18, 0x1F3027, 0x2C4235, 0x9FCFA8)),
        ["sunset"] = new(new(0xFBF0E8, 0xFFFAF6, 0xF0DECF, 0x9F442C), new(0x281B20, 0x3D2930, 0x533840, 0xFFB08E)),
        ["rose"] = new(new(0xF8EEF0, 0xFFF9FB, 0xEFDBE1, 0x9B3F60), new(0x25191F, 0x39262F, 0x4D3440, 0xF2ACC5)),
        ["midnight"] = new(new(0xEEF0FA, 0xFAFBFF, 0xDFE4F3, 0x4E56A6), new(0x11162B, 0x1E2842, 0x2D3957, 0xADBFFF)),
    };
}

public sealed record CompanionAppearance(string Theme = "warm", bool Dark = false)
{
    public ThemePalette Palette => Dark || Theme == "amoled" ? AppTheme.All[Theme].Dark : AppTheme.All[Theme].Light;
    public static CompanionAppearance? Parse(string? theme, string? appearance) =>
        theme is not null && AppTheme.All.ContainsKey(theme) && appearance is "light" or "dark"
            ? new(theme, theme == "amoled" || appearance == "dark") : null;
}
