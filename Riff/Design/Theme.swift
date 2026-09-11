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
    static let colors = ["orange", "purple", "blue", "green", "pink"]
    static func color(_ name: String) -> Color {
        switch name {
        case "purple": Color(red: 0.81, green: 0.75, blue: 0.95)
        case "blue": Color(red: 0.68, green: 0.83, blue: 0.94)
        case "green": Color(red: 0.75, green: 0.86, blue: 0.62)
        case "pink": Color(red: 0.98, green: 0.70, blue: 0.72)
        default: Color(red: 1.0, green: 0.76, blue: 0.38)
        }
    }
}

enum AppTheme: String, CaseIterable, Identifiable {
    case warm, ocean, orchid, graphite
    var id: String { rawValue }
    var name: String {
        switch self {
        case .warm: "Warm"
        case .ocean: "Ocean"
        case .orchid: "Orchid"
        case .graphite: "Graphite"
        }
    }
    var colors: ThemeColors {
        switch self {
        case .warm: ThemeColors(canvas: (0xF6F3EE, 0x191918), surface: (0xFFFFFF, 0x272725), inset: (0xEAE6DF, 0x343431), highlight: (0xBA382F, 0xFF968B))
        case .ocean: ThemeColors(canvas: (0xECF3F5, 0x111C22), surface: (0xF9FDFE, 0x1E3039), inset: (0xDCE9EE, 0x2A414C), highlight: (0x00677C, 0x75CFDE))
        case .orchid: ThemeColors(canvas: (0xF5EFF7, 0x201922), surface: (0xFEFBFF, 0x322737), inset: (0xEADFEF, 0x44364A), highlight: (0x81509B, 0xD5AFF0))
        case .graphite: ThemeColors(canvas: (0xF0F1F3, 0x15171B), surface: (0xFFFFFF, 0x25282E), inset: (0xE1E3E7, 0x343940), highlight: (0x425D8A, 0xA8BFE7))
        }
    }
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
