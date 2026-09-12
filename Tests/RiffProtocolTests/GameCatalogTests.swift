import Testing
@testable import RiffProtocol

@MainActor struct GameCatalogTests {
    @Test func mergesGamesByIDAndUsesTheLatestNames() {
        let catalog = GameCatalog(companionID: "pc-a", games: [SteamGame(id: "730", name: "Old name"), SteamGame(id: "570", name: "Dota 2")])
        let next = catalog.updating(with: [SteamGame(id: "730", name: "Counter-Strike 2"), SteamGame(id: "620", name: "Portal 2")], companionID: "pc-a")
        #expect(next.games.map(\.id) == ["730", "570", "620"])
        #expect(next.games.first?.name == "Counter-Strike 2")
        #expect(next.updating(with: [], companionID: "pc-a").games == next.games)
    }

    @Test func anotherPCGetsItsOwnCatalog() {
        let catalog = GameCatalog(companionID: "pc-a", games: [SteamGame(id: "730", name: "Counter-Strike 2")])
        let next = catalog.updating(with: [SteamGame(id: "620", name: "Portal 2")], companionID: "pc-b")
        #expect(next.companionID == "pc-b")
        #expect(next.games.map(\.id) == ["620"])
        #expect(catalog.updating(with: [], companionID: "pc-b").games.isEmpty)
    }
}
