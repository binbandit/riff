import Foundation

enum ActionKind: String, CaseIterable, Identifiable {
    case sound, hotkey, text, url, app, media, macro
    case actionSwitch = "switch"
    case random, deck, back, stop
    var isSequence: Bool { [.macro, .actionSwitch, .random].contains(self) }
    var isGestureAction: Bool { isStep || [.deck, .back, .stop].contains(self) }
    var isStep: Bool { [.sound, .hotkey, .text, .url, .app, .media].contains(self) }
    var needsDeckActions: Bool { [.actionSwitch, .random, .deck, .back, .stop].contains(self) }
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
        case .actionSwitch: "Action switch"
        case .random: "Random action"
        case .deck: "Open deck"
        case .back: "Go back"
        case .stop: "Stop all"
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
        case .actionSwitch: "switch.2"
        case .random: "shuffle"
        case .deck: "folder"
        case .back: "arrow.uturn.backward"
        case .stop: "stop.fill"
        }
    }
}
