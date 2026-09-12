import Foundation
import Testing
@testable import RiffProtocol

@MainActor struct LayoutSharingTests {
    private var source: Snapshot {
        var state = Snapshot.starter
        state.capabilities = ["deck-actions-v1", "pinned-pads-v1"]
        state.apps = [LaunchApp(id: "source-app", name: "OBS Studio")]
        state.decks[0].steamAppId = "730"; state.decks[0].linkedAppId = "source-app"
        state.decks[0].pads = [
            Pad(id: "switch", title: "Stream", kind: "switch", value: "", steps: [ActionStep(kind: "sound", value: "nope")],
                alternateSteps: [ActionStep(kind: "app", value: "source-app"), ActionStep(kind: "sound", value: "nope", delayMs: 100)], pinned: true),
            Pad(id: "self", title: "Home", kind: "deck", value: state.decks[0].id),
            Pad(id: "other", title: "Everyday", kind: "deck", value: state.decks[1].id),
            Pad(id: "text", title: "Greeting", kind: "text", value: "Hello,\nworld!")
        ]
        return state
    }
    private func package(_ state: Snapshot) throws -> DeckPackage {
        try DeckPackage.make(deck: state.decks[0], snapshot: state, grid: GridPreferences(columns: 4, rows: 2))
    }

    @Test func deckFileRoundTripsAndContainsOnlyLayoutResources() throws {
        let state = source
        let shared = try package(state)
        let data = try shared.encoded()
        let decoded = try DeckPackage.read(data)
        #expect(decoded.grid == GridPreferences(columns: 4, rows: 2))
        #expect(decoded.deck.steamAppId.isEmpty && decoded.deck.linkedAppId == nil)
        #expect(decoded.deck.pads[0].isPinned)
        #expect(decoded.deck.pads[0].alternateSteps?.last?.delayMs == 100)
        #expect(decoded.deck.pads[3].value == "Hello,\nworld!")
        #expect(Set(decoded.dependencies.map(\.id)) == ["sound:nope", "app:source-app", "deck:everyday"])
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(json.keys) == ["format", "schemaVersion", "content", "deck", "grid", "dependencies"])
    }

    @Test func importingRelinksBothSwitchSidesAndSelfNavigationWithFreshIDs() throws {
        let shared = try package(source)
        var destination = Snapshot.starter
        destination.capabilities = source.capabilities
        destination.clips = [Clip(id: "new-sound", name: "Nope", duration: 1)]
        destination.apps = [LaunchApp(id: "new-app", name: "OBS Studio")]
        destination.decks[1].id = "new-everyday"
        let matches = shared.suggestedMatches(in: destination)
        #expect(matches == ["sound:nope": "new-sound", "app:source-app": "new-app", "deck:everyday": "new-everyday"])
        let imported = try shared.importedDeck(name: "Studio", matches: matches, snapshot: destination)
        #expect(imported.id != shared.deck.id && imported.linkedAppId == nil && imported.steamAppId.isEmpty)
        #expect(imported.pads[0].steps[0].value == "new-sound")
        #expect(imported.pads[0].alternateSteps?[0].value == "new-app")
        #expect(imported.pads[0].alternateSteps?[1].value == "new-sound")
        #expect(imported.pads[1].value == imported.id && imported.pads[2].value == "new-everyday")
        #expect(Set(imported.pads.map(\.id)).isDisjoint(with: shared.deck.pads.map(\.id)))
        let again = try shared.importedDeck(name: "Studio", matches: matches, snapshot: destination)
        #expect(again.id != imported.id && Set(again.pads.map(\.id)).isDisjoint(with: imported.pads.map(\.id)))
    }

    @Test func ambiguousNamesAndUnrelatedMatchingIDsRequireExplicitSelection() throws {
        let shared = try package(source)
        var destination = source
        destination.clips = [Clip(id: "a", name: "Nope", duration: 1), Clip(id: "b", name: "Nope", duration: 1)]
        destination.apps = [LaunchApp(id: "source-app", name: "A different app")]
        let matches = shared.suggestedMatches(in: destination)
        #expect(matches["sound:nope"] == nil && matches["app:source-app"] == nil)
        #expect(shared.missingMatches(matches, in: destination).count == 2)
        #expect(throws: (any Error).self) { try shared.importedDeck(name: "Studio", matches: matches, snapshot: destination) }
        var resolved = matches; resolved["sound:nope"] = "b"; resolved["app:source-app"] = "source-app"
        #expect(shared.missingMatches(resolved, in: destination).isEmpty)
        destination.apps = []
        #expect(throws: (any Error).self) { try shared.importedDeck(name: "Studio", matches: resolved, snapshot: destination) }
    }

    @Test func singleButtonSharingPreservesOriginalDeckReferencesAndAppendsWithoutReplacing() throws {
        let state = source
        let shared = try DeckPackage.make(deck: state.decks[0], snapshot: state, grid: GridPreferences(), button: state.decks[0].pads[1])
        #expect(shared.content == "button" && shared.deck.pads.count == 1)
        #expect(shared.dependencies.first?.value == state.decks[0].id)
        let imported = try shared.importedDeck(name: shared.deck.name, into: state.decks[1].id, matches: shared.suggestedMatches(in: state), snapshot: state)
        #expect(imported.id == state.decks[1].id && Array(imported.pads.dropLast()) == state.decks[1].pads)
        #expect(imported.pads.last?.value == state.decks[0].id)
    }

    @Test func importsRespectCapacityCapabilityAndLegacyWireLimits() throws {
        var state = source
        let shared = try package(state)
        state.capabilities = []
        #expect(shared.compatibilityIssue(in: state) != nil)
        state.capabilities = ["deck-actions-v1"]
        #expect(shared.compatibilityIssue(in: state)?.contains("pinned") == true)
        state.capabilities = source.capabilities
        state.decks[1].pads = (0..<48).map { _ in Pad() }
        #expect(throws: (any Error).self) { try shared.importedDeck(name: "Studio", into: state.decks[1].id, matches: shared.suggestedMatches(in: state), snapshot: state) }
        state.decks += (0..<18).map { _ in Deck() }
        #expect(throws: (any Error).self) { try shared.importedDeck(name: "Studio", matches: shared.suggestedMatches(in: state), snapshot: state) }
        let simple = try DeckPackage.make(deck: Deck(pads: [Pad(kind: "text", value: "Hello", pinned: false)]), snapshot: Snapshot.starter, grid: GridPreferences())
        let imported = try simple.importedDeck(name: "Legacy", matches: [:], snapshot: Snapshot.starter)
        let text = String(decoding: try JSONEncoder().encode(imported), as: UTF8.self)
        #expect(!text.contains("pinned") && !text.contains("alternateSteps") && !text.contains("linkedAppId"))
    }

    @Test func rejectsMalformedFutureOversizedAndInconsistentLayouts() throws {
        let valid = try package(source)
        #expect(throws: (any Error).self) { try DeckPackage.read(Data("{}".utf8)) }
        #expect(throws: (any Error).self) { try DeckPackage.read(Data(repeating: 0, count: DeckPackage.maximumBytes + 1)) }
        var bad = valid; bad.schemaVersion = 999
        #expect(throws: (any Error).self) { try bad.validate() }
        bad = valid; bad.deck.pads.append(bad.deck.pads[0])
        #expect(throws: (any Error).self) { try bad.validate() }
        bad = valid; bad.dependencies.append(bad.dependencies[0])
        #expect(throws: (any Error).self) { try bad.validate() }
        bad = valid; bad.dependencies.removeAll()
        #expect(throws: (any Error).self) { try bad.validate() }
        bad = valid; bad.deck.pads[0].alternateSteps = [ActionStep(kind: "macro", value: "")]
        #expect(throws: (any Error).self) { try bad.validate() }
        bad = valid; bad.deck.pads[0].alternateSteps = [ActionStep(kind: "text", value: "Hi", delayMs: Int.max)]
        #expect(throws: (any Error).self) { try bad.validate() }
        bad = valid; bad.deck.pads[3].kind = "url"; bad.deck.pads[3].value = "file:///C:/Windows/cmd.exe"
        #expect(throws: (any Error).self) { try bad.validate() }
        bad = valid; bad.grid.columns = -1
        #expect(throws: (any Error).self) { try bad.validate() }
    }

    @Test func retryIdentitiesPreventDuplicateImportsAfterALostResponse() throws {
        let shared = try package(source)
        let ids = Dictionary(uniqueKeysWithValues: shared.deck.pads.map { ($0.id, UUID().uuidString) })
        let destination = UUID().uuidString
        var snapshot = source
        let first = try shared.importedDeck(name: "Studio", matches: shared.suggestedMatches(in: snapshot), snapshot: snapshot, newDeckID: destination, buttonIDs: ids)
        let retry = try shared.importedDeck(name: "Studio", matches: shared.suggestedMatches(in: snapshot), snapshot: snapshot, newDeckID: destination, buttonIDs: ids)
        #expect(first.id == retry.id && first.pads.map(\.id) == retry.pads.map(\.id))
        snapshot.decks.append(first)
        #expect(throws: (any Error).self) {
            try shared.importedDeck(name: "Studio", matches: shared.suggestedMatches(in: snapshot), snapshot: snapshot, newDeckID: destination, buttonIDs: ids)
        }
        // Choosing another target after the interrupted request must not add the same import twice.
        #expect(throws: (any Error).self) {
            try shared.importedDeck(name: "Studio", into: snapshot.decks[1].id, matches: shared.suggestedMatches(in: snapshot), snapshot: snapshot, newDeckID: destination, buttonIDs: ids)
        }
    }

    @Test func pinsAndImportedLayoutsStaySavedWhenCompanionSyncFails() async throws {
        let folder = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let cache = folder.appendingPathComponent("snapshot.json")
        var initial = Snapshot.starter
        initial.capabilities = ["deck-actions-v1", "pinned-pads-v1"]
        try JSONEncoder().encode(initial).write(to: cache)
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/companion_state_server.py").path, cache.path]
        let pipe = Pipe(); process.standardOutput = pipe
        try process.run()
        defer { process.terminate(); process.waitUntilExit() }
        let pairing = try JSONDecoder().decode(Pairing.self, from: pipe.fileHandleForReading.availableData)
        let store = RiffStore(cacheURL: cache, pairing: pairing)
        await store.refresh()
        await store.setPinned(true, pad: initial.decks[0].pads[0])
        await store.refresh()
        #expect(store.snapshot.decks[0].pads[0].isPinned)
        let shared = try package(store.snapshot)
        let imported = try shared.importedDeck(name: "Imported", matches: shared.suggestedMatches(in: store.snapshot), snapshot: store.snapshot)
        let before = store.snapshot.decks
        let client = CompanionClient(pairing: pairing)
        let _: Acknowledgement = try await client.request("/test/fail-next-deck-save")
        try await store.saveDecks(before + [imported])
        #expect(store.snapshot.decks == before + [imported] && !store.busy && store.hasPendingDeckChanges)
        let pending = RiffStore(cacheURL: cache, pairing: nil)
        #expect(pending.snapshot.decks == store.snapshot.decks && pending.hasPendingDeckChanges)
        await store.refresh()
        #expect(store.hasPendingDeckChanges)
        await store.refresh()
        #expect(!store.hasPendingDeckChanges)
        #expect(store.snapshot.decks.count == before.count + 1)
        #expect(store.snapshot.decks.last?.pads.first?.isPinned == true)
        await store.setPinned(false, pad: initial.decks[0].pads[0])
        let restored = RiffStore(cacheURL: cache, pairing: nil)
        #expect(!restored.snapshot.decks[0].pads[0].isPinned)
        #expect(restored.snapshot.decks.last?.pads.first?.isPinned == true)
        #expect(restored.snapshot.decks.last?.pads.map(\.value) == initial.decks[0].pads.map(\.value))
    }
}
