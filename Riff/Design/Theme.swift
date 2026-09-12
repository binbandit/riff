import Foundation
import SwiftUI
import Observation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum Palette {
    static var background: Color { ThemePreferences.shared.theme.colors.background }
    static var panel: Color { ThemePreferences.shared.theme.colors.panel }
    static var raised: Color { ThemePreferences.shared.theme.colors.raised }
    static var accent: Color { ThemePreferences.shared.theme.colors.accent }
    static var accentInk: Color { ThemeColor.adaptive(light: 0xFFFFFF, dark: 0x14191D) }
    static let ink = Color(red: 0.19, green: 0.16, blue: 0.15)
    static let colors = ["orange", "purple", "blue", "green", "pink", "coral", "peach", "yellow", "mint", "teal", "indigo", "sand"]
    static func color(_ name: String) -> Color {
        switch name {
        case "purple": Color(red: 0.81, green: 0.75, blue: 0.95)
        case "blue": Color(red: 0.68, green: 0.83, blue: 0.94)
        case "green": Color(red: 0.75, green: 0.86, blue: 0.62)
        case "pink": Color(red: 0.98, green: 0.70, blue: 0.72)
        case "coral": Color(red: 0.96, green: 0.61, blue: 0.53)
        case "peach": Color(red: 1.0, green: 0.82, blue: 0.68)
        case "yellow": Color(red: 0.97, green: 0.88, blue: 0.55)
        case "mint": Color(red: 0.69, green: 0.88, blue: 0.77)
        case "teal": Color(red: 0.55, green: 0.79, blue: 0.78)
        case "indigo": Color(red: 0.67, green: 0.71, blue: 0.90)
        case "sand": Color(red: 0.86, green: 0.80, blue: 0.70)
        default: Color(red: 1.0, green: 0.76, blue: 0.38)
        }
    }
}

enum AppTheme: String, CaseIterable, Identifiable {
    case warm, ocean, orchid, graphite, amoled, forest, sunset, rose, midnight
    var id: String { rawValue }
    var name: String {
        switch self {
        case .warm: "Warm"
        case .ocean: "Ocean"
        case .orchid: "Orchid"
        case .graphite: "Graphite"
        case .amoled: "AMOLED"
        case .forest: "Forest"
        case .sunset: "Sunset"
        case .rose: "Rose"
        case .midnight: "Midnight"
        }
    }
    var colors: ThemeColors {
        switch self {
        case .warm: ThemeColors(canvas: (0xF6F3EE, 0x191918), surface: (0xFFFFFF, 0x272725), inset: (0xEAE6DF, 0x343431), highlight: (0xBA382F, 0xFF968B))
        case .ocean: ThemeColors(canvas: (0xECF3F5, 0x111C22), surface: (0xF9FDFE, 0x1E3039), inset: (0xDCE9EE, 0x2A414C), highlight: (0x00677C, 0x75CFDE))
        case .orchid: ThemeColors(canvas: (0xF5EFF7, 0x201922), surface: (0xFEFBFF, 0x322737), inset: (0xEADFEF, 0x44364A), highlight: (0x81509B, 0xD5AFF0))
        case .graphite: ThemeColors(canvas: (0xF0F1F3, 0x15171B), surface: (0xFFFFFF, 0x25282E), inset: (0xE1E3E7, 0x343940), highlight: (0x425D8A, 0xA8BFE7))
        case .amoled: ThemeColors(canvas: (0x000000, 0x000000), surface: (0x000000, 0x000000), inset: (0x121212, 0x121212), highlight: (0xA8BFE7, 0xA8BFE7))
        case .forest: ThemeColors(canvas: (0xEEF3EB, 0x111D18), surface: (0xFAFCF7, 0x1F3027), inset: (0xDDE7D7, 0x2C4235), highlight: (0x326344, 0x9FCFA8))
        case .sunset: ThemeColors(canvas: (0xFBF0E8, 0x281B20), surface: (0xFFFAF6, 0x3D2930), inset: (0xF0DECF, 0x533840), highlight: (0x9F442C, 0xFFB08E))
        case .rose: ThemeColors(canvas: (0xF8EEF0, 0x25191F), surface: (0xFFF9FB, 0x39262F), inset: (0xEFDBE1, 0x4D3440), highlight: (0x9B3F60, 0xF2ACC5))
        case .midnight: ThemeColors(canvas: (0xEEF0FA, 0x11162B), surface: (0xFAFBFF, 0x1E2842), inset: (0xDFE4F3, 0x2D3957), highlight: (0x4E56A6, 0xADBFFF))
        }
    }

    var colorScheme: ColorScheme? { self == .amoled ? .dark : nil }

    func padBackground(_ tint: Color) -> Color { self == .amoled ? .black : tint }
    func padForeground(_ tint: Color) -> Color { self == .amoled ? tint : Palette.ink }
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var name: String { rawValue.capitalized }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

@MainActor @Observable final class ThemePreferences {
    static let shared = ThemePreferences()
    private let defaults: UserDefaults
    var theme: AppTheme { didSet { defaults.set(theme.rawValue, forKey: "riff.theme") } }
    var appearance: AppAppearance { didSet { defaults.set(appearance.rawValue, forKey: "riff.appearance") } }
    var colorScheme: ColorScheme? { theme.colorScheme ?? appearance.colorScheme }
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        theme = defaults.string(forKey: "riff.theme").flatMap(AppTheme.init(rawValue:)) ?? .warm
        appearance = defaults.string(forKey: "riff.appearance").flatMap(AppAppearance.init(rawValue:)) ?? .system
    }
}

struct ThemeColors {
    let canvas: (light: Int, dark: Int)
    let surface: (light: Int, dark: Int)
    let inset: (light: Int, dark: Int)
    let highlight: (light: Int, dark: Int)
    var background: Color { ThemeColor.adaptive(light: canvas.light, dark: canvas.dark) }
    var panel: Color { ThemeColor.adaptive(light: surface.light, dark: surface.dark) }
    var raised: Color { ThemeColor.adaptive(light: inset.light, dark: inset.dark) }
    var accent: Color { ThemeColor.adaptive(light: highlight.light, dark: highlight.dark) }
}

private enum ThemeColor {
    static func adaptive(light: Int, dark: Int) -> Color {
#if canImport(UIKit)
        Color(uiColor: UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: 1)
        })
#elseif canImport(AppKit)
        Color(nsColor: NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: 1)
        })
#endif
    }
}
