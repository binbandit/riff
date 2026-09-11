import Foundation
import SwiftUI
import Observation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct ActionStep: Codable, Hashable, Identifiable {
    var kind = "hotkey"
    var value = "Ctrl+Shift+M"
    var delayMs = 0
    var id = UUID().uuidString
    enum CodingKeys: String, CodingKey { case kind, value, delayMs }
}
struct Pad: Codable, Identifiable, Hashable {
    var id = UUID().uuidString
    var title = "New button"
    var icon = "sparkles"
    var color = "orange"
    var kind = "sound"
    var value = "level-up"
    var steps: [ActionStep] = []
    var tint: Color { Palette.color(color) }
    var typeName: String { ActionKind(rawValue: kind)?.label ?? "Action" }
    func duplicated() -> Pad {
        var copy = self
        copy.id = UUID().uuidString
        // Leave room for the suffix within the companion's UTF-16 title limit.
        while copy.title.utf16.count > 33 { copy.title.removeLast() }
        copy.title += " (copy)"
        copy.steps = steps.map { step in
            var next = step; next.id = UUID().uuidString; return next
        }
        return copy
    }
}
struct Deck: Codable, Identifiable, Hashable {
    var id = UUID().uuidString
    var name = "New deck"
    var icon = "square.grid.2x2"
    var pads: [Pad] = []
    var steamAppId = ""
}
struct Clip: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var duration: Double
    var buttonTitle: String {
        var title = name
        while title.utf16.count > 40 { title.removeLast() }
        return title
    }
}
struct AudioOutput: Codable, Identifiable, Hashable { var id: String; var name: String }
struct LaunchApp: Codable, Identifiable, Hashable { var id: String; var name: String }
struct SteamGame: Codable, Identifiable, Hashable { var id: String; var name: String }
struct Snapshot: Codable {
    var version: Int
    var decks: [Deck]
    var clips: [Clip]
    var outputs: [AudioOutput]
    var outputId: String
    var volume: Float
    var apps: [LaunchApp]
    var computerName: String
    var games: [SteamGame]
    var activeGameId: String
    var activeGameName: String
    var capabilities: [String]? = nil
    var companionVersion: String? = nil
    var soundboardOnly: Bool? = nil
    func blocksDesktopAction(_ pad: Pad) -> Bool { soundboardOnly == true && pad.kind != "sound" }
    func decksSaving(_ pad: Pad, in deckId: String) throws -> [Deck] {
        var result = decks
        guard let target = result.firstIndex(where: { $0.id == deckId }) else { throw RiffError.message("This deck no longer exists.") }
        if let existing = result[target].pads.firstIndex(where: { $0.id == pad.id }) {
            result[target].pads[existing] = pad
        } else {
            guard result[target].pads.count < 48 else { throw RiffError.message("This deck has 48 buttons. Choose another deck or remove a button first.") }
            for index in result.indices where index != target { result[index].pads.removeAll { $0.id == pad.id } }
            result[target].pads.append(pad)
        }
        return result
    }
}
enum ActionKind: String, CaseIterable, Identifiable {
    case sound, hotkey, text, url, app, media, macro
    var id: String { rawValue }
    var label: String {
        switch self {
        case .sound: "Play a sound"
        case .hotkey: "Keyboard shortcut"
        case .text: "Type text"
        case .url: "Open website"
        case .app: "Launch app"
        case .media: "Media control"
        case .macro: "Action sequence"
        }
    }
    var icon: String {
        switch self {
        case .sound: "waveform"
        case .hotkey: "command"
        case .text: "text.bubble"
        case .url: "globe"
        case .app: "app"
        case .media: "playpause"
        case .macro: "square.stack.3d.up"
        }
    }
}
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

struct PadGlyph: View {
    let icon: String
    var size: CGFloat = 64
    var body: some View {
        if icon.hasPrefix("emoji:") {
            Text(String(icon.dropFirst(6))).font(.system(size: size))
        } else {
            Image(systemName: icon).font(.system(size: size, weight: .medium, design: .rounded))
                .symbolRenderingMode(.hierarchical)
        }
    }
}
extension Snapshot {
    static let starter = Snapshot(version: 0, decks: [
        Deck(id: "soundboard", name: "Soundboard", icon: "waveform", pads: [
            Pad(id: "level-up-pad", title: "Level up", icon: "sparkles", color: "orange", value: "level-up"),
            Pad(id: "plot-twist-pad", title: "Plot twist", icon: "theatermasks", color: "purple", value: "plot-twist"),
            Pad(id: "nope-pad", title: "Nope", icon: "hand.raised", color: "pink", value: "nope"),
            Pad(id: "countdown-pad", title: "Countdown", icon: "timer", color: "blue", value: "countdown"),
            Pad(id: "coin-drop-pad", title: "Coin drop", icon: "circle.circle", color: "green", value: "coin-drop"),
            Pad(id: "red-alert-pad", title: "Red alert", icon: "light.beacon.max", color: "orange", value: "red-alert")
        ]),
        Deck(id: "everyday", name: "Everyday", icon: "command", pads: [
            Pad(id: "play-pause-pad", title: "Play / pause", icon: "playpause", color: "green", kind: "media", value: "playPause"),
            Pad(id: "next-pad", title: "Next track", icon: "forward.end", color: "blue", kind: "media", value: "next"),
            Pad(id: "mute-pad", title: "Mute audio", icon: "speaker.slash", color: "pink", kind: "media", value: "mute"),
            Pad(id: "desktop-pad", title: "Show desktop", icon: "desktopcomputer", color: "purple", kind: "hotkey", value: "Win+D"),
            Pad(id: "screenshot-pad", title: "Screenshot", icon: "viewfinder", color: "orange", kind: "hotkey", value: "Win+Shift+S"),
            Pad(id: "gg-pad", title: "Good game", icon: "text.bubble", color: "green", kind: "text", value: "gg, well played!")
        ])
    ], clips: [Clip(id: "level-up", name: "Level up", duration: 0.76), Clip(id: "plot-twist", name: "Plot twist", duration: 1.21), Clip(id: "nope", name: "Nope", duration: 0.53), Clip(id: "countdown", name: "Countdown", duration: 1.8), Clip(id: "coin-drop", name: "Coin drop", duration: 0.39), Clip(id: "red-alert", name: "Red alert", duration: 1.44)], outputs: [], outputId: "", volume: 0.75, apps: [], computerName: "", games: [], activeGameId: "", activeGameName: "")
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
