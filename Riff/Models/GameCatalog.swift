import Foundation

/// Games remain useful for configuring decks even when a Steam library drive is
/// unavailable. Keep games seen on this PC; a newly paired PC gets its own list.
struct GameCatalog: Codable {
    var companionID: String?
    var games: [SteamGame]

    func updating(with discovered: [SteamGame], companionID nextID: String?) -> GameCatalog {
        let previous = companionID == nextID ? games : []
        var byID: [String: SteamGame] = [:]
        for game in previous + discovered { byID[game.id] = game }
        let sorted = byID.values.sorted {
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
        return GameCatalog(companionID: nextID, games: sorted)
    }
}
