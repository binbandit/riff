import Foundation
import Testing
@testable import RiffProtocol

@MainActor struct DeckSuggestionTests {
    private func button(_ pad: Pad, pack: String? = nil, sound: String? = nil) -> DeckSuggestedButton {
        DeckSuggestedButton(pad: pad, reason: "Fits this space.", description: "A sound", packId: pack, soundId: sound)
    }

    @Test func createsOnlySelectedButtonsWithoutChangingExistingDecks() throws {
        let state = Snapshot.starter
        let chosen = button(Pad(title: "Reaction", icon: "waveform", value: state.clips[0].id))
        let deck = Deck(name: "Game night", steamAppId: "730")
        let result = try SuggestedDeckBuilder.decks(adding: deck, buttons: [chosen], to: state)
        #expect(Array(result.dropLast()) == state.decks)
        #expect(result.last?.pads == [chosen.pad] && result.last?.steamAppId == "730")
        #expect(try SuggestedDeckBuilder.decks(adding: deck, buttons: [], to: state).last?.pads.isEmpty == true)
        #expect(throws: (any Error).self) { try SuggestedDeckBuilder.decks(adding: state.decks[0], buttons: [], to: state) }
        #expect(throws: (any Error).self) { try SuggestedDeckBuilder.decks(adding: deck, buttons: [chosen, chosen], to: state) }
    }

    @Test func rejectsMissingSoundsAndChangedSoundboardMode() throws {
        var state = Snapshot.starter
        #expect(throws: (any Error).self) { try SuggestedDeckBuilder.decks(adding: Deck(), buttons: [button(Pad(value: "missing"))], to: state) }
        state.soundboardOnly = true
        #expect(throws: (any Error).self) { try SuggestedDeckBuilder.decks(adding: Deck(), buttons: [button(Pad(kind: "hotkey", value: "Ctrl+M"))], to: state) }
    }

    @Test func packReferencesMustMatchActualBundledAudio() throws {
        let packs = try SoundPacks.load()
        let pack = try #require(packs.first), sound = try #require(pack.sounds.first)
        let valid = button(Pad(value: sound.clipID), pack: pack.id, sound: sound.id)
        #expect(try valid.packSound(in: packs)?.1.clipID == sound.clipID)
        let invalid = button(Pad(value: "different"), pack: pack.id, sound: sound.id)
        #expect(throws: (any Error).self) { try invalid.packSound(in: packs) }
    }

    @Test func includedSoundsNeedNoTransferAndSuggestionsAreReadOnly() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let cache = folder.appendingPathComponent("snapshot.json")
        var state = Snapshot.starter
        state.capabilities = ["deck-suggestions-v1", "pad-suggestions-enabled-v1", "bundled-sounds-v1"]
        try JSONEncoder().encode(state).write(to: cache)
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/companion_state_server.py").path, cache.path]
        let pipe = Pipe(); process.standardOutput = pipe
        try process.run()
        defer { process.terminate(); process.waitUntilExit() }
        let pairing = try JSONDecoder().decode(Pairing.self, from: pipe.fileHandleForReading.availableData)
        let store = RiffStore(cacheURL: cache, pairing: pairing)
        await store.refresh()
        let suggestion = try await store.suggestDeck(DeckSuggestionRequest(gameId: "730", appId: "", name: "", intent: "Reactions"))
        #expect(store.snapshot.decks == state.decks && store.snapshot.clips == state.clips && !store.busy)
        let selected = try #require(suggestion.buttons.first(where: { $0.packId != nil }))
        let deck = Deck(name: suggestion.name, icon: suggestion.icon, steamAppId: "730")
        let client = CompanionClient(pairing: pairing)
        let _: Acknowledgement = try await client.request("/test/fail-next-deck-save")
        try await store.createSuggestedDeck(deck, buttons: [selected])
        #expect(store.hasPendingDeckChanges && store.snapshot.clips.count == state.clips.count && !store.busy)
        #expect(store.snapshot.decks.last?.pads == [selected.pad])
        for _ in 0..<3 where store.hasPendingDeckChanges { await store.refresh() }
        #expect(!store.hasPendingDeckChanges)
        #expect(store.snapshot.clips.count == state.clips.count)
        #expect(store.snapshot.decks.last?.pads == [selected.pad])
        #expect(store.snapshot.decks.last?.steamAppId == "730")
        #expect(store.selectedDeckId == deck.id && !store.busy)
        #expect(Array(store.snapshot.decks.dropLast()) == state.decks)
    }

    @Test func emptyDeckCreationStillWorksOffline() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = RiffStore(cacheURL: folder.appendingPathComponent("state.json"), pairing: nil)
        let deck = Deck(name: "Offline space")
        try await store.createSuggestedDeck(deck, buttons: [])
        #expect(store.snapshot.decks.last?.id == deck.id && store.hasPendingDeckChanges)
    }
}
