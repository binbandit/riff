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
    @Test func groupsCoverEverySoundOnceAndKeepRenamedClipsInTheirGroup() throws {
        var clips = Snapshot.starter.clips
        let index = try #require(clips.firstIndex { $0.id == "pack-sad-violin" })
        clips[index].name = "My reaction"
        clips.append(Clip(id: "recording", name: "My recording", duration: 1))
        let groups = SoundCatalog.groups(clips)
        #expect(groups.count == 16)
        #expect(groups.first?.name == "My sounds")
        #expect(groups.flatMap(\.clips).count == clips.count)
        #expect(Set(groups.flatMap(\.clips).map(\.id)).count == clips.count)
        #expect(groups.first { $0.id == "epic-fails" }?.clips.contains { $0.name == "My reaction" } == true)
        #expect(SoundCatalog.groups([]).isEmpty)
    }

}
