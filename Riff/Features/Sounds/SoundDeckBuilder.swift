import Foundation

enum SoundDeckTarget {
    case existing(String)
    case new(id: String, name: String, icon: String)
}

struct SoundDeckAddition {
    let decks: [Deck]
    let deckID: String
    let added: [Clip]
    let skipped: Int

    init(snapshot: Snapshot, clipIDs: [String], target: SoundDeckTarget) throws {
        var seen = Set<String>()
        let ids = clipIDs.filter { seen.insert($0).inserted }
        guard !ids.isEmpty else { throw RiffError.message("Choose at least one sound.") }
        let clips = try ids.map { id in
            guard let clip = snapshot.clips.first(where: { $0.id == id }) else {
                throw RiffError.message("A selected sound was removed. Go back and choose your sounds again.")
            }
            return clip
        }
        var decks = snapshot.decks
        let index: Int
        switch target {
        case .existing(let id):
            guard let found = decks.firstIndex(where: { $0.id == id }) else {
                throw RiffError.message("This deck was removed. Choose another deck.")
            }
            index = found
        case .new(let id, let name, let icon):
            let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty && name.utf16.count <= 40 else {
                throw RiffError.message("Give your deck a name of up to 40 characters.")
            }
            guard decks.count < 20 else { throw RiffError.message("You have 20 decks. Choose an existing deck or remove one first.") }
            guard !decks.contains(where: { $0.id == id }) else { throw RiffError.message("This deck already exists. Choose it from the list.") }
            index = decks.count
            decks.append(Deck(id: id, name: name, icon: icon))
        }
        let used = Set(decks[index].pads.filter { $0.kind == "sound" }.map(\.value))
        let additions = clips.filter { !used.contains($0.id) }
        let available = max(0, 48 - decks[index].pads.count)
        guard additions.count <= available else {
            throw RiffError.message("This deck has room for \(available) more buttons. Choose another deck or fewer sounds.")
        }
        let offset = decks[index].pads.count
        decks[index].pads += additions.enumerated().map { number, clip in
            Pad(title: clip.buttonTitle, icon: "waveform", color: Palette.colors[(offset + number) % Palette.colors.count], value: clip.id)
        }
        self.decks = decks
        deckID = decks[index].id
        added = additions
        skipped = clips.count - additions.count
    }
}
