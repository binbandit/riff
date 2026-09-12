import Foundation

struct DeckSuggestionRequest: Codable, Hashable {
    let gameId: String
    let appId: String
    let name: String
    let intent: String
    var hasContext: Bool { !(gameId + appId + name + intent).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

struct DeckSuggestedButton: Codable, Identifiable {
    let pad: Pad
    let reason: String
    let description: String
    let packId: String?
    let soundId: String?
    var id: String { pad.id }

    func packSound(in packs: [SoundPack]) throws -> (SoundPack, PackSound)? {
        guard packId != nil || soundId != nil else { return nil }
        guard let pack = packs.first(where: { $0.id == packId }),
              let sound = pack.sounds.first(where: { $0.id == soundId }), pad.kind == "sound", sound.clipID == pad.value else {
            throw RiffError.message("A suggested sound is no longer available. Refresh the suggestions.")
        }
        return (pack, sound)
    }
}

struct DeckSuggestion: Codable {
    let name: String
    let icon: String
    let summary: String
    let buttons: [DeckSuggestedButton]
    static let icons = ["waveform", "gamecontroller", "airplane", "face.smiling", "command", "square.grid.2x2", "video"]

    func validated() throws -> Self {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.utf16.count <= 40,
              Self.icons.contains(icon), (1...12).contains(buttons.count), Set(buttons.map(\.id)).count == buttons.count else {
            throw RiffError.message("AI returned a deck Riff cannot use. Try again.")
        }
        for button in buttons {
            _ = try PadSuggestion(label: button.pad.title, icon: button.pad.icon, color: button.pad.color).validated()
            guard !button.id.isEmpty, ActionKind(rawValue: button.pad.kind) != nil else { throw RiffError.message("AI returned an unknown button.") }
        }
        return self
    }
}

enum SuggestedDeckBuilder {
    static func decks(adding deck: Deck, buttons: [DeckSuggestedButton], to snapshot: Snapshot) throws -> [Deck] {
        guard snapshot.decks.count < 20 else { throw RiffError.message("You have 20 decks. Remove one before creating another.") }
        guard !snapshot.decks.contains(where: { $0.id == deck.id }) else { throw RiffError.message("This deck already exists. Open it to make changes.") }
        guard deck.pads.count + buttons.count <= 48, Set(buttons.map(\.id)).count == buttons.count else { throw RiffError.message("Choose up to 48 distinct buttons.") }
        for button in buttons {
            if button.pad.kind == "sound", !snapshot.clips.contains(where: { $0.id == button.pad.value }) {
                throw RiffError.message("A suggested sound is missing. Refresh the suggestions and try again.")
            }
            if snapshot.blocksDesktopAction(button.pad) { throw RiffError.message("Soundboard mode changed. Refresh the suggestions to use available buttons.") }
        }
        var result = deck
        result.pads += buttons.map(\.pad)
        return snapshot.decks + [result]
    }
}
