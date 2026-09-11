import Foundation
import SwiftUI

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
    static let background = Color("Canvas")
    static let panel = Color("Surface")
    static let raised = Color("Inset")
    static let accent = Color(red: 0.84, green: 0.23, blue: 0.20)
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
