import Foundation

enum ButtonPresetCategory: String, CaseIterable, Identifiable {
    case media = "Music & audio"
    case windows = "Windows"
    case editing = "Everyday editing"
    case browser = "Browser"
    case chat = "Game chat"
    case riff = "Riff controls"
    var id: String { rawValue }
}

struct ButtonPreset: Identifiable {
    let id: String
    let category: ButtonPresetCategory
    let title: String
    let icon: String
    let color: String
    let kind: ActionKind
    let value: String
    let detail: String

    func makePad(chatKey: String = "K") -> Pad {
        let steps = category == .chat ? [
            ActionStep(kind: "hotkey", value: chatKey),
            ActionStep(kind: "text", value: value, delayMs: 300),
            ActionStep(kind: "hotkey", value: "Enter", delayMs: 100)
        ] : []
        return Pad(title: title, icon: icon, color: color, kind: kind.rawValue,
                   value: kind.isSequence ? "" : value, steps: steps)
    }

    func matches(_ query: String) -> Bool {
        let words = query.split(whereSeparator: \.isWhitespace)
        let content = "\(title) \(category.rawValue) \(detail) \(value)"
        return words.allSatisfy { content.localizedStandardContains(String($0)) }
    }

    func unavailableReason(supportsDeckActions: Bool) -> String? {
        kind.needsDeckActions && !supportsDeckActions ? "Update the Windows companion to add this control." : nil
    }

    static let chatKeys = ["K", "T", "Y", "Enter"]

    static let all: [ButtonPreset] = [
        .init(id: "play-pause", category: .media, title: "Play / pause", icon: "playpause", color: "green", kind: .media, value: "playPause", detail: "Pause or resume your music."),
        .init(id: "next-track", category: .media, title: "Next track", icon: "forward.end", color: "blue", kind: .media, value: "next", detail: "Skip to the next track."),
        .init(id: "previous-track", category: .media, title: "Previous track", icon: "backward.end", color: "blue", kind: .media, value: "previous", detail: "Return to the previous track."),
        .init(id: "volume-up", category: .media, title: "Volume up", icon: "speaker.plus", color: "green", kind: .media, value: "volumeUp", detail: "Raise your PC's volume."),
        .init(id: "volume-down", category: .media, title: "Volume down", icon: "speaker.minus", color: "orange", kind: .media, value: "volumeDown", detail: "Lower your PC's volume."),
        .init(id: "mute", category: .media, title: "Mute / unmute", icon: "speaker.slash", color: "pink", kind: .media, value: "mute", detail: "Toggle your PC's audio mute."),

        .init(id: "desktop", category: .windows, title: "Show desktop", icon: "desktopcomputer", color: "purple", kind: .hotkey, value: "Win+D", detail: "Hide or restore your open windows."),
        .init(id: "screenshot", category: .windows, title: "Screenshot", icon: "viewfinder", color: "orange", kind: .hotkey, value: "Win+Shift+S", detail: "Choose an area of the screen to capture."),
        .init(id: "explorer", category: .windows, title: "File Explorer", icon: "folder", color: "orange", kind: .hotkey, value: "Win+E", detail: "Open your files and folders."),
        .init(id: "settings", category: .windows, title: "Windows settings", icon: "gearshape", color: "blue", kind: .hotkey, value: "Win+I", detail: "Open Windows settings."),
        .init(id: "switch-app", category: .windows, title: "Switch app", icon: "rectangle.on.rectangle", color: "purple", kind: .hotkey, value: "Alt+Tab", detail: "Switch to your last used window."),
        .init(id: "task-view", category: .windows, title: "Task view", icon: "rectangle.3.group", color: "blue", kind: .hotkey, value: "Win+Tab", detail: "See open windows and virtual desktops."),

        .init(id: "copy", category: .editing, title: "Copy", icon: "doc.on.doc", color: "blue", kind: .hotkey, value: "Ctrl+C", detail: "Copy the selected text or item."),
        .init(id: "paste", category: .editing, title: "Paste", icon: "doc.on.clipboard", color: "green", kind: .hotkey, value: "Ctrl+V", detail: "Paste from your clipboard."),
        .init(id: "cut", category: .editing, title: "Cut", icon: "scissors", color: "orange", kind: .hotkey, value: "Ctrl+X", detail: "Cut the selected text or item."),
        .init(id: "undo", category: .editing, title: "Undo", icon: "arrow.uturn.backward", color: "purple", kind: .hotkey, value: "Ctrl+Z", detail: "Undo the last edit in the focused app."),
        .init(id: "redo", category: .editing, title: "Redo", icon: "arrow.uturn.forward", color: "purple", kind: .hotkey, value: "Ctrl+Y", detail: "Redo an edit in apps that use Ctrl+Y."),
        .init(id: "select-all", category: .editing, title: "Select all", icon: "selection.pin.in.out", color: "blue", kind: .hotkey, value: "Ctrl+A", detail: "Select everything in the focused field or view."),
        .init(id: "find", category: .editing, title: "Find", icon: "magnifyingglass", color: "orange", kind: .hotkey, value: "Ctrl+F", detail: "Find text in the focused app or page."),
        .init(id: "save", category: .editing, title: "Save", icon: "square.and.arrow.down", color: "green", kind: .hotkey, value: "Ctrl+S", detail: "Save the current document or page."),
        .init(id: "bold", category: .editing, title: "Bold", icon: "bold", color: "pink", kind: .hotkey, value: "Ctrl+B", detail: "Toggle bold in a text editor."),
        .init(id: "italic", category: .editing, title: "Italic", icon: "italic", color: "pink", kind: .hotkey, value: "Ctrl+I", detail: "Toggle italic in a text editor."),
        .init(id: "underline", category: .editing, title: "Underline", icon: "underline", color: "pink", kind: .hotkey, value: "Ctrl+U", detail: "Toggle underline in a text editor."),
        .init(id: "paste-plain", category: .editing, title: "Paste plain text", icon: "textformat", color: "green", kind: .hotkey, value: "Ctrl+Shift+V", detail: "Paste without formatting in supported apps."),

        .init(id: "new-tab", category: .browser, title: "New tab", icon: "plus.square", color: "green", kind: .hotkey, value: "Ctrl+T", detail: "Open a new browser tab."),
        .init(id: "reopen-tab", category: .browser, title: "Reopen tab", icon: "arrow.counterclockwise", color: "purple", kind: .hotkey, value: "Ctrl+Shift+T", detail: "Restore the most recently closed tab."),
        .init(id: "next-tab", category: .browser, title: "Next tab", icon: "arrow.right.square", color: "blue", kind: .hotkey, value: "Ctrl+Tab", detail: "Move to the next browser tab."),
        .init(id: "previous-tab", category: .browser, title: "Previous tab", icon: "arrow.left.square", color: "blue", kind: .hotkey, value: "Ctrl+Shift+Tab", detail: "Move to the previous browser tab."),
        .init(id: "address", category: .browser, title: "Address bar", icon: "link", color: "orange", kind: .hotkey, value: "Ctrl+L", detail: "Select the address bar to search or enter a URL."),
        .init(id: "refresh", category: .browser, title: "Refresh page", icon: "arrow.clockwise", color: "green", kind: .hotkey, value: "Ctrl+R", detail: "Reload the current page."),
        .init(id: "browser-back", category: .browser, title: "Previous page", icon: "chevron.left", color: "purple", kind: .hotkey, value: "Alt+Left", detail: "Go back in browser history."),
        .init(id: "browser-forward", category: .browser, title: "Next page", icon: "chevron.right", color: "purple", kind: .hotkey, value: "Alt+Right", detail: "Go forward in browser history."),

        .init(id: "chat-gg", category: .chat, title: "Good game", icon: "hand.thumbsup", color: "green", kind: .macro, value: "GG", detail: "Open game chat, type GG, then send."),
        .init(id: "chat-glhf", category: .chat, title: "Good luck", icon: "sparkles", color: "orange", kind: .macro, value: "GLHF!", detail: "Send good luck, have fun to the chat."),
        .init(id: "chat-nice", category: .chat, title: "Nice shot", icon: "scope", color: "blue", kind: .macro, value: "Nice shot!", detail: "Send a quick compliment."),
        .init(id: "chat-thanks", category: .chat, title: "Thanks", icon: "heart", color: "pink", kind: .macro, value: "Thanks!", detail: "Thank your teammates."),
        .init(id: "chat-brb", category: .chat, title: "Be right back", icon: "clock", color: "purple", kind: .macro, value: "BRB", detail: "Let the team know you're stepping away."),
        .init(id: "chat-ready", category: .chat, title: "Ready", icon: "checkmark.circle", color: "green", kind: .macro, value: "Ready!", detail: "Tell the team you're ready to go."),

        .init(id: "stop-all", category: .riff, title: "Stop all", icon: "stop.fill", color: "pink", kind: .stop, value: "", detail: "Stop Riff sounds, clear the queue, and cancel sequences."),
        .init(id: "go-back", category: .riff, title: "Go back", icon: "arrow.uturn.backward", color: "purple", kind: .back, value: "", detail: "Return to the deck you opened this one from.")
    ]
}

enum PresetDeckBuilder {
    static func decks(adding presetIDs: [String], to deckID: String, snapshot: Snapshot,
                      chatKey: String = "K", supportsDeckActions: Bool) throws -> [Deck] {
        guard !presetIDs.isEmpty else { throw RiffError.message("Choose at least one preset.") }
        var seen = Set<String>()
        let presets = try presetIDs.filter { seen.insert($0).inserted }.map { id in
            guard let preset = ButtonPreset.all.first(where: { $0.id == id }) else {
                throw RiffError.message("A selected preset is no longer available.")
            }
            if let reason = preset.unavailableReason(supportsDeckActions: supportsDeckActions) { throw RiffError.message(reason) }
            return preset
        }
        if presets.contains(where: { $0.category == .chat }), !ButtonPreset.chatKeys.contains(chatKey) {
            throw RiffError.message("Choose a game chat key. You can customize other keys in the button editor after adding.")
        }
        var result = snapshot
        for preset in presets {
            result.decks = try result.decksSaving(preset.makePad(chatKey: chatKey), in: deckID)
        }
        return result.decks
    }
}
