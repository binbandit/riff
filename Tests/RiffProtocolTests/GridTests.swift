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
}
