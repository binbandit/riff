import Foundation
import Testing
@testable import RiffProtocol

@MainActor struct ButtonPresetTests {
    @Test func catalogCreatesPortableButtonsWithFreshIdentities() throws {
        #expect(Set(ButtonPreset.all.map(\.id)).count == ButtonPreset.all.count)
        for preset in ButtonPreset.all {
            let first = preset.makePad()
            let second = preset.makePad()
            #expect(first.id != second.id)
            #expect(Set(first.steps.map(\.id)).isDisjoint(with: second.steps.map(\.id)))
            let deck = Deck(name: "Presets", pads: [first, second])
            let package = try DeckPackage.make(deck: deck, snapshot: .starter, grid: GridPreferences())
            let restored = try DeckPackage.read(package.encoded())
            #expect(restored.deck.pads.map(\.title) == [preset.title, preset.title])
        }
    }

    @Test func batchPreservesSelectionOrderAndExistingButtons() throws {
        let snapshot = Snapshot.starter
        let result = try PresetDeckBuilder.decks(adding: ["chat-gg", "copy", "next-track", "copy"],
                                                to: "everyday", snapshot: snapshot, chatKey: "T", supportsDeckActions: true)
        #expect(result[0] == snapshot.decks[0])
        #expect(Array(result[1].pads.prefix(6)) == snapshot.decks[1].pads)
        let added = Array(result[1].pads.dropFirst(6))
        #expect(added.map(\.title) == ["Good game", "Copy", "Next track"])
        #expect(added[0].value.isEmpty)
        #expect(added[0].steps.map(\.kind) == ["hotkey", "text", "hotkey"])
        #expect(added[0].steps.map(\.value) == ["T", "GG", "Enter"])
        #expect(added[0].steps.map(\.delayMs) == [0, 300, 100])
    }

    @Test func batchRejectsOverflowMissingDecksAndUnavailableControls() throws {
        var snapshot = Snapshot.starter
        snapshot.decks[0].pads = (0..<47).map { _ in Pad() }
        #expect(throws: (any Error).self) {
            try PresetDeckBuilder.decks(adding: ["copy", "paste"], to: "soundboard", snapshot: snapshot, supportsDeckActions: true)
        }
        #expect(snapshot.decks[0].pads.count == 47)
        let full = try PresetDeckBuilder.decks(adding: ["copy"], to: "soundboard", snapshot: snapshot, supportsDeckActions: false)
        #expect(full[0].pads.count == 48)
        for ids in [[], ["missing"], ["stop-all"], ["copy", "go-back"]] {
            #expect(throws: (any Error).self) {
                try PresetDeckBuilder.decks(adding: ids, to: "everyday", snapshot: snapshot, supportsDeckActions: false)
            }
        }
        #expect(throws: (any Error).self) {
            try PresetDeckBuilder.decks(adding: ["copy"], to: "missing", snapshot: snapshot, supportsDeckActions: true)
        }
        #expect(throws: (any Error).self) {
            try PresetDeckBuilder.decks(adding: ["chat-gg"], to: "everyday", snapshot: snapshot, chatKey: "", supportsDeckActions: true)
        }
    }

    @Test func searchFindsTitlesCategoriesAndShortcuts() {
        #expect(ButtonPreset.all.filter { $0.matches("ctrl shift t") }.map(\.id).contains("reopen-tab"))
        #expect(ButtonPreset.all.filter { $0.matches("game chat") }.allSatisfy { $0.category == .chat })
        #expect(ButtonPreset.all.filter { $0.matches("SCREENSHOT") }.map(\.id) == ["screenshot"])
        #expect(ButtonPreset.all.filter { $0.matches("  ") }.count == ButtonPreset.all.count)
        #expect(ButtonPreset.all.filter { $0.matches("no such preset") }.isEmpty)
    }

    @Test func batchSavesOfflineAndSurvivesRestart() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let cache = folder.appendingPathComponent("snapshot.json")
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = RiffStore(cacheURL: cache, pairing: nil)
        let decks = try PresetDeckBuilder.decks(adding: ["play-pause", "chat-thanks", "stop-all"],
                                               to: store.selectedDeckId, snapshot: store.snapshot,
                                               supportsDeckActions: store.supportsDeckActions)
        try await store.saveDecks(decks)
        let restored = RiffStore(cacheURL: cache, pairing: nil)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        #expect(try encoder.encode(restored.snapshot.decks) == encoder.encode(decks))
        #expect(restored.hasPendingDeckChanges)
    }
}
