import Foundation
import Testing
@testable import RiffProtocol

@MainActor struct GridTests {
    @Test func automaticRotatesWithoutChangingCapacity() {
        let portrait = BoardLayout(size: CGSize(width: 834, height: 1100), preferences: GridPreferences())
        let landscape = BoardLayout(size: CGSize(width: 1194, height: 750), preferences: GridPreferences())
        #expect(portrait.columns == 2)
        #expect(landscape.columns == 3)
        #expect(portrait.capacity == 6 && landscape.capacity == 6)
    }

    @Test func customGridKeepsCapacityInSmallWindows() {
        let layout = BoardLayout(size: CGSize(width: 320, height: 480), preferences: GridPreferences(columns: 6, rows: 5))
        #expect(layout.capacity == 30)
        #expect(layout.gridWidth > 320)
        #expect(layout.padHeight >= 110)
    }

    @Test func preferencesRoundTripPerDeck() throws {
        let saved = ["pilot": GridPreferences(columns: 3, rows: 2), "memes": GridPreferences(columns: 4, rows: 4)]
        let decoded = try JSONDecoder().decode([String: GridPreferences].self, from: JSONEncoder().encode(saved))
        #expect(decoded == saved)
        let bounds = GridPreferences(columns: -1, rows: 100).dimensions(portrait: true)
        #expect(bounds.columns == 1 && bounds.rows == 6)
    }

    @Test func playModeMakesRoomWithoutChangingPages() {
        let size = CGSize(width: 1194, height: 750)
        let preferences = GridPreferences(columns: 3, rows: 2)
        let regular = BoardLayout(size: size, preferences: preferences)
        let playing = BoardLayout(size: size, preferences: preferences, playMode: true)
        #expect(playing.padHeight > regular.padHeight)
        #expect(playing.capacity == regular.capacity)
        #expect(playing.columns == regular.columns)
        #expect(playing.gridWidth == regular.gridWidth)
        let small = BoardLayout(size: CGSize(width: 320, height: 480), preferences: GridPreferences(columns: 6, rows: 6), playMode: true)
        #expect(small.capacity == 36 && small.padHeight >= 110)
    }

    @Test func remembersEachDeckAndKeepsSoundsVisibleWhenGridChanges() {
        var memory = DeckPageMemory()
        memory.select(2, deckID: "pilot", capacity: 6, padCount: 24)
        memory.select(1, deckID: "memes", capacity: 4, padCount: 12)
        #expect(memory.page(deckID: "pilot", capacity: 6, padCount: 24) == 2)
        #expect(memory.page(deckID: "memes", capacity: 4, padCount: 12) == 1)
        #expect(memory.page(deckID: "pilot", capacity: 4, padCount: 24) == 3)
        #expect(memory.page(deckID: "new", capacity: 6, padCount: 24) == 0)
    }

    @Test func clampsPagesAfterRemovalAndForEmptyDecks() {
        var memory = DeckPageMemory()
        memory.select(7, deckID: "pilot", capacity: 6, padCount: 48)
        #expect(memory.page(deckID: "pilot", capacity: 6, padCount: 7) == 1)
        #expect(memory.page(deckID: "pilot", capacity: 6, padCount: 0) == 0)
        memory.select(-1, deckID: "pilot", capacity: 6, padCount: 48)
        #expect(memory.page(deckID: "pilot", capacity: 6, padCount: 48) == 0)
        memory.select(100, deckID: "pilot", capacity: 6, padCount: 13)
        #expect(memory.page(deckID: "pilot", capacity: 6, padCount: 13) == 2)
    }
}
