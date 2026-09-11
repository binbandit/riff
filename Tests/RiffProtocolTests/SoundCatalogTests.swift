import Testing
@testable import RiffProtocol

@MainActor struct SoundCatalogTests {
    let clips = [Clip(id: "radio", name: "Radio check", duration: 2), Clip(id: "takeoff", name: "Prêt for takeoff", duration: 3), Clip(id: "meme", name: "Bruh", duration: 1)]

    @Test func searchesWithinFavoritesAndIgnoresMissingFavorites() {
        let matches = SoundCatalog.visible(clips, query: " PRET ", scope: .favorites, favorites: ["takeoff", "deleted"], deck: nil)
        #expect(matches.map(\.id) == ["takeoff"])
        #expect(SoundCatalog.visible(clips, query: "radio", scope: .favorites, favorites: ["takeoff"], deck: nil).isEmpty)
    }

    @Test func deckFilterIncludesSequenceSoundsWithoutDuplicates() {
        let deck = Deck(pads: [Pad(kind: "sound", value: "radio"), Pad(kind: "macro", steps: [ActionStep(kind: "sound", value: "takeoff"), ActionStep(kind: "sound", value: "radio")]), Pad(kind: "text", value: "meme")])
        let matches = SoundCatalog.visible(clips, query: "", scope: .deck, favorites: [], deck: deck)
        #expect(matches.map(\.id) == ["takeoff", "radio"])
        #expect(SoundCatalog.visible(clips, query: "", scope: .deck, favorites: [], deck: nil).isEmpty)
    }
}
