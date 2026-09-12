import Foundation

struct SoundSuggestionRequest: Codable, Hashable {
    let clipIds: [String]
    let deckName: String
    var gameId = ""
    var appId = ""
}

struct SoundButtonSuggestion: Codable {
    let clipId: String
    let label: String
    let icon: String
    let color: String
    var appearance: PadSuggestion { PadSuggestion(label: label, icon: icon, color: color) }
}

struct SoundSuggestionBatch: Codable {
    let buttons: [SoundButtonSuggestion]

    func appearances(for clipIDs: [String]) throws -> [String: PadSuggestion] {
        var result: [String: PadSuggestion] = [:]
        guard !clipIDs.isEmpty, clipIDs.count <= 48, Set(clipIDs).count == clipIDs.count,
              buttons.count == clipIDs.count else { throw RiffError.message("AI did not return all the selected sounds. Try again or use the current buttons.") }
        for button in buttons {
            guard clipIDs.contains(button.clipId), result[button.clipId] == nil else {
                throw RiffError.message("AI returned a different set of sounds. Try again or use the current buttons.")
            }
            result[button.clipId] = try button.appearance.validated()
        }
        return result
    }
}

// Keep each manual field independent so a late suggestion can still fill the other fields.
struct SoundButtonEdits {
    var label: String?
    var icon: String?
    var color: String?

    func applying(to pad: Pad) -> Pad {
        var pad = pad
        if let label { pad.title = label }
        if let icon { pad.icon = icon }
        if let color { pad.color = color }
        return pad
    }
}
