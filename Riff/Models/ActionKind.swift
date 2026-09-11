import Foundation

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
