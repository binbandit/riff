import Foundation

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
