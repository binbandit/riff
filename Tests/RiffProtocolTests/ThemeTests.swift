import Foundation
import Testing
@testable import RiffProtocol

@MainActor struct ThemeTests {
    @Test func preferencesPersistAndUnknownValuesFallBack() throws {
        let name = "RiffThemeTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = ThemePreferences(defaults: defaults)
        #expect(preferences.theme == .warm)
        #expect(preferences.appearance == .system)
        preferences.theme = .ocean
        preferences.appearance = .dark
        let restored = ThemePreferences(defaults: defaults)
        #expect(restored.theme == .ocean)
        #expect(restored.appearance == .dark)
        defaults.set("removed-theme", forKey: "riff.theme")
        defaults.set("unknown-appearance", forKey: "riff.appearance")
        let fallback = ThemePreferences(defaults: defaults)
        #expect(fallback.theme == .warm)
        #expect(fallback.appearance == .system)
    }

    @Test func everyAccentHasReadableTextAndButtonContrast() {
        for theme in AppTheme.allCases {
            let colours = theme.colors
            if theme.colorScheme != .dark {
                for backdrop in [colours.canvas.light, colours.surface.light] {
                    #expect(contrast(colours.highlight.light, backdrop) >= 4.5, "\(theme.name) light accent text")
                }
                #expect(contrast(colours.highlight.light, 0xFFFFFF) >= 4.5, "\(theme.name) light button label")
            }
            for backdrop in [colours.canvas.dark, colours.surface.dark] {
                #expect(contrast(colours.highlight.dark, backdrop) >= 4.5, "\(theme.name) dark accent text")
            }
            #expect(contrast(colours.highlight.dark, 0x14191D) >= 4.5, "\(theme.name) dark button label")
        }
    }

    @Test(arguments: AppAppearance.allCases)
    func amoledStaysDarkAndPreservesAppearance(appearance: AppAppearance) throws {
        let name = "RiffThemeTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = ThemePreferences(defaults: defaults)
        preferences.appearance = appearance
        preferences.theme = .amoled
        #expect(preferences.colorScheme == .dark)

        let restored = ThemePreferences(defaults: defaults)
        #expect(restored.theme == .amoled)
        #expect(restored.colorScheme == .dark)
        #expect(restored.appearance == appearance)
        restored.theme = .warm
        #expect(restored.colorScheme == appearance.colorScheme)
    }

    @Test func companionFollowsDisplayedAppearanceAndAMOLEDOverride() throws {
        let name = "RiffThemeTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = ThemePreferences(defaults: defaults)
        preferences.displayedColorScheme = .dark
        #expect(preferences.companionAppearance == "dark")
        preferences.appearance = .light
        #expect(preferences.companionAppearance == "light")
        preferences.theme = .amoled
        #expect(preferences.companionAppearance == "dark")
        preferences.theme = .ocean
        #expect(preferences.companionAppearance == "light")
        preferences.appearance = .system
        preferences.displayedColorScheme = .light
        #expect(preferences.companionAppearance == "light")
    }

    private func contrast(_ first: Int, _ second: Int) -> Double {
        let a = luminance(first), b = luminance(second)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
    private func luminance(_ value: Int) -> Double {
        let rgb = [16, 8, 0].map { shift -> Double in
            let channel = Double((value >> shift) & 255) / 255
            return channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return rgb[0] * 0.2126 + rgb[1] * 0.7152 + rgb[2] * 0.0722
    }
}
