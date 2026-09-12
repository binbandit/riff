import Foundation

struct SmartProfiles {
    private var lastContext: String?

    mutating func selection(in snapshot: Snapshot, followApps: Bool, followGames: Bool, paused: Bool) -> String? {
        guard !paused else { return nil }
        let app = followApps ? snapshot.activeAppId ?? "" : ""
        let game = followGames ? snapshot.activeGameId : ""
        let appDeck = app.isEmpty ? nil : snapshot.decks.first { $0.linkedAppId == app }
        let context = appDeck != nil ? "app:\(app)" : "game:\(game)"
        defer { lastContext = context }
        guard context != lastContext else { return nil }
        if let appDeck { return appDeck.id }
        return game.isEmpty ? nil : snapshot.decks.first { $0.steamAppId == game }?.id
    }
}
