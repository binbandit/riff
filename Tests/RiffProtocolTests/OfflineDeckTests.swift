import Foundation
import Testing
@testable import RiffProtocol

@MainActor struct OfflineDeckTests {
    @MainActor private final class Fixture {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        var cache: URL { folder.appendingPathComponent("snapshot.json") }
        let process = Process()
        let pairing: Pairing
        let client: CompanionClient
        init(state: Snapshot = .starter) throws {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = folder.appendingPathComponent("snapshot.json")
            try JSONEncoder().encode(state).write(to: file)
            process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            process.arguments = [URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/companion_state_server.py").path, file.path]
            let pipe = Pipe(); process.standardOutput = pipe
            try process.run()
            pairing = try JSONDecoder().decode(Pairing.self, from: pipe.fileHandleForReading.availableData)
            client = CompanionClient(pairing: pairing)
        }
        func close() { process.terminate(); process.waitUntilExit(); try? FileManager.default.removeItem(at: folder) }
        func signal(_ path: String) async throws {
            let result: Acknowledgement = try await client.request("/test/\(path)")
            #expect(result.ok)
        }
        func state() async throws -> Snapshot { try await client.request("/api/state") }
        func save(_ decks: [Deck]) async throws {
            struct Update: Encodable { let version: Int; let decks: [Deck] }
            let current = try await state()
            let _: Snapshot = try await client.request("/api/decks", method: "PUT", body: JSONEncoder().encode(Update(version: current.version, decks: decks)))
        }
    }

    @Test func discoveredGamesAppsAndOutputsRemainUsableForOfflineDeckCreation() async throws {
        var pc = Snapshot.starter
        pc.games = [SteamGame(id: "730", name: "Counter-Strike 2")]
        pc.apps = [LaunchApp(id: "discord", name: "Discord")]
        pc.outputs = [AudioOutput(id: "headphones", name: "Headphones")]
        pc.capabilities = ["smart-profiles-v1"]
        pc.computerName = "Gaming PC"
        let fixture = try Fixture(state: pc); defer { fixture.close() }
        // Start without any local knowledge; the first connection discovers it.
        try JSONEncoder().encode(Snapshot.starter).write(to: fixture.cache)
        let store = RiffStore(cacheURL: fixture.cache, pairing: fixture.pairing)
        await store.refresh()
        try await fixture.signal("fail-next-state")
        await store.refresh()
        #expect(!store.connected)
        #expect(store.snapshot.games == pc.games && store.snapshot.apps == pc.apps)
        #expect(store.snapshot.outputs == pc.outputs && store.snapshot.computerName == pc.computerName)
        let offline = RiffStore(cacheURL: fixture.cache, pairing: nil)
        #expect(offline.snapshot.games == pc.games && offline.snapshot.apps == pc.apps)
        #expect(offline.snapshot.outputs == pc.outputs)
        let deck = Deck(name: offline.snapshot.games[0].name,
                        pads: [Pad(title: "Open Discord", kind: "app", value: offline.snapshot.apps[0].id)],
                        steamAppId: offline.snapshot.games[0].id, linkedAppId: offline.snapshot.apps[0].id)
        try await offline.createSuggestedDeck(deck, buttons: [])
        #expect(offline.hasPendingDeckChanges)
        let restarted = RiffStore(cacheURL: fixture.cache, pairing: fixture.pairing)
        #expect(restarted.snapshot.decks.last?.steamAppId == "730")
        #expect(restarted.snapshot.decks.last?.linkedAppId == "discord")
        await restarted.refresh()
        #expect(!restarted.hasPendingDeckChanges)
        let saved = try await fixture.state()
        #expect(saved.decks.last?.steamAppId == "730" && saved.decks.last?.linkedAppId == "discord")
        #expect(saved.decks.last?.pads.first?.value == "discord")
    }

    @Test func emptyGameScansKeepKnownGamesButAppPermissionsStayCurrent() async throws {
        var pc = Snapshot.starter
        pc.games = [SteamGame(id: "730", name: "Counter-Strike")]
        pc.apps = [LaunchApp(id: "old-app", name: "Old app")]
        let fixture = try Fixture(state: pc); defer { fixture.close() }
        let store = RiffStore(cacheURL: fixture.cache, pairing: fixture.pairing)
        await store.refresh()
        struct Catalog: Encodable { var games: [SteamGame]; var apps: [LaunchApp] }
        let _: Snapshot = try await fixture.client.request("/test/catalog", method: "POST", body: JSONEncoder().encode(Catalog(games: [], apps: [])))
        await store.refresh()
        #expect(store.snapshot.games == pc.games)
        #expect(store.snapshot.apps.isEmpty)
        let restored = RiffStore(cacheURL: fixture.cache, pairing: fixture.pairing)
        #expect(restored.snapshot.games == pc.games)
        let newer = [SteamGame(id: "730", name: "Counter-Strike 2"), SteamGame(id: "570", name: "Dota 2")]
        let _: Snapshot = try await fixture.client.request("/test/catalog", method: "POST", body: JSONEncoder().encode(Catalog(games: newer, apps: [LaunchApp(id: "new-app", name: "New app")])))
        await restored.refresh()
        #expect(restored.snapshot.games == newer)
        #expect(restored.snapshot.apps.map(\.id) == ["new-app"])
        #expect(RiffStore(cacheURL: fixture.cache, pairing: nil).snapshot.games == newer)
    }

    @Test func createsEditsMovesPinsAndDeletesOfflineAcrossRestarts() async throws {
        let fixture = try Fixture(); defer { fixture.close() }
        let store = RiffStore(cacheURL: fixture.cache, pairing: nil)
        let deck = Deck(name: "Offline deck")
        try await store.createSuggestedDeck(deck, buttons: [])
        var pad = store.snapshot.decks[0].pads[0]; pad.title = "My reaction"
        try await store.savePad(pad, in: deck.id)
        await store.setPinned(true, pad: pad)
        var decks = store.snapshot.decks
        decks[0].name = "My sounds"; decks[1].pads.removeLast()
        try await store.saveDecks(decks)
        #expect(!store.connected && store.hasPendingDeckChanges)
        let restored = RiffStore(cacheURL: fixture.cache, pairing: fixture.pairing)
        #expect(DeckChanges.same(restored.snapshot.decks, store.snapshot.decks))
        #expect(restored.snapshot.decks.last?.pads.first?.isPinned == true)
        #expect(restored.snapshot.decks[0].pads.count == 5 && restored.snapshot.decks[1].pads.count == 5)
        // This fixture represents an updated companion before reconnecting.
        // Pin capability is checked separately below; unpin before syncing to this legacy fixture.
        var unpinned = restored.snapshot.decks; unpinned[2].pads[0].pinned = nil
        try await restored.saveDecks(unpinned)
        await restored.refresh()
        #expect(restored.connected && !restored.hasPendingDeckChanges)
        #expect(DeckChanges.same(try await fixture.state().decks, unpinned))
        #expect(!RiffStore(cacheURL: fixture.cache, pairing: nil).hasPendingDeckChanges)
        try await restored.saveDecks(Array(restored.snapshot.decks.dropLast()))
        await restored.refresh()
        #expect(try await fixture.state().decks.count == 2)
    }

    @Test func reconnectMergesOtherDeviceEditsAndKeepsPCSettings() async throws {
        let fixture = try Fixture(); defer { fixture.close() }
        let store = RiffStore(cacheURL: fixture.cache, pairing: fixture.pairing)
        var local = store.snapshot.decks
        local[0].name = "On iPad"; local[0].pads[0].title = "Local title"
        local[0].pads.remove(at: 1)
        local.append(Deck(name: "Created offline"))
        try await store.saveDecks(local)
        var remote = Snapshot.starter.decks
        remote[0].name = "PC title"; remote[0].pads[0].title = "PC button title"
        remote[0].icon = "gamecontroller"; remote[0].pads[0].color = "green"
        remote[1].pads.removeLast(); remote.append(Deck(name: "Created on PC"))
        try await fixture.save(remote)
        await store.refresh()
        let saved = try await fixture.state()
        #expect(saved.decks.count == 4)
        #expect(saved.decks[0].name == "On iPad" && saved.decks[0].icon == "gamecontroller")
        #expect(saved.decks[0].pads[0].title == "Local title" && saved.decks[0].pads[0].color == "green")
        #expect(saved.decks[0].pads.count == 5 && saved.decks[1].pads.count == 5)
        #expect(saved.volume == Snapshot.starter.volume && !store.hasPendingDeckChanges)
        let version = saved.version
        await store.refresh()
        #expect(try await fixture.state().version == version)
    }

    @Test func failedOnlineSaveRemainsDurableAndRetriesAfterRestart() async throws {
        let fixture = try Fixture(); defer { fixture.close() }
        let store = RiffStore(cacheURL: fixture.cache, pairing: fixture.pairing)
        await store.refresh()
        try await fixture.signal("fail-next-deck-save")
        let deck = Deck(name: "Keep me")
        try await store.saveDecks(store.snapshot.decks + [deck])
        await store.refresh()
        #expect(store.hasPendingDeckChanges && store.deckSyncIssue != nil)
        #expect(try await fixture.state().decks.count == 2)
        let restored = RiffStore(cacheURL: fixture.cache, pairing: fixture.pairing)
        #expect(restored.snapshot.decks.last?.id == deck.id)
        await restored.refresh()
        #expect(!restored.hasPendingDeckChanges && restored.deckSyncIssue == nil)
        #expect(try await fixture.state().decks.last?.id == deck.id)
    }

    @Test func lostAcknowledgementDoesNotDuplicateDecksOrRepeatTheWrite() async throws {
        let fixture = try Fixture(); defer { fixture.close() }
        let store = RiffStore(cacheURL: fixture.cache, pairing: fixture.pairing)
        await store.refresh()
        try await fixture.signal("lose-next-deck-ack")
        try await store.saveDecks(store.snapshot.decks + [Deck(name: "Once")])
        await store.refresh()
        #expect(store.hasPendingDeckChanges)
        let committed = try await fixture.state()
        let restored = RiffStore(cacheURL: fixture.cache, pairing: fixture.pairing)
        await restored.refresh()
        #expect(!restored.hasPendingDeckChanges)
        #expect(try await fixture.state().version == committed.version)
        #expect(restored.snapshot.decks.count == 3)
    }

    @Test func retriesVersionConflictsWithoutOverwritingOtherDecks() async throws {
        let fixture = try Fixture(); defer { fixture.close() }
        let store = RiffStore(cacheURL: fixture.cache, pairing: fixture.pairing)
        await store.refresh()
        try await fixture.signal("conflict-next-deck-save")
        var decks = store.snapshot.decks; decks[0].name = "Changed on iPad"
        try await store.saveDecks(decks)
        await store.refresh()
        #expect(!store.hasPendingDeckChanges)
        let saved = try await fixture.state()
        #expect(saved.decks[0].name == "Changed on iPad" && saved.decks[1].name == "Changed on PC")
    }

    @Test func editingDuringAnUploadSavesImmediatelyAndRejectsTheOlderResponse() async throws {
        let fixture = try Fixture(); defer { fixture.close() }
        let store = RiffStore(cacheURL: fixture.cache, pairing: fixture.pairing)
        await store.refresh()
        try await fixture.signal("hold-next-deck-save")
        let deck = Deck(name: "First edit")
        try await store.saveDecks(store.snapshot.decks + [deck])
        try await fixture.signal("deck-save-started")
        #expect(!store.busy)
        var newer = store.snapshot.decks; newer[2].name = "Second edit"
        try await store.saveDecks(newer)
        #expect(RiffStore(cacheURL: fixture.cache, pairing: nil).snapshot.decks[2].name == "Second edit")
        try await fixture.signal("release-deck-save")
        await store.refresh()
        await store.refresh()
        #expect(!store.busy && !store.hasPendingDeckChanges)
        #expect(store.snapshot.decks[2].name == "Second edit")
        #expect(try await fixture.state().decks[2].name == "Second edit")
    }

    @Test func stalePollCannotReplaceAnOfflineEdit() async throws {
        let fixture = try Fixture(); defer { fixture.close() }
        let store = RiffStore(cacheURL: fixture.cache, pairing: fixture.pairing)
        try await fixture.signal("hold-next-state")
        let poll = Task { await store.refresh() }
        try await fixture.signal("state-started")
        var decks = store.snapshot.decks; decks[0].name = "Still here"
        try await store.saveDecks(decks)
        try await fixture.signal("release-state")
        await poll.value
        #expect(!store.connected && store.hasPendingDeckChanges && store.snapshot.decks[0].name == "Still here")
        await store.refresh()
        #expect(!store.hasPendingDeckChanges && store.snapshot.decks[0].name == "Still here")
    }

    @Test func unsupportedCompanionKeepsEditsForLater() async throws {
        let fixture = try Fixture(); defer { fixture.close() }
        let store = RiffStore(cacheURL: fixture.cache, pairing: fixture.pairing)
        var decks = store.snapshot.decks; decks[0].pads[0].pinned = true
        try await store.saveDecks(decks)
        await store.refresh()
        #expect(store.connected && store.hasPendingDeckChanges)
        #expect(store.deckSyncIssue?.contains("Update") == true)
        #expect(store.snapshot.decks[0].pads[0].isPinned)
        #expect(try await fixture.state().decks[0].pads[0].isPinned == false)
    }

    @Test func localWriteFailureDoesNotReportASuccessfulSave() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data("not a directory".utf8).write(to: folder)
        let store = RiffStore(cacheURL: folder.appendingPathComponent("snapshot.json"), pairing: nil)
        do { try await store.saveDecks(store.snapshot.decks + [Deck()]); Issue.record("Expected a storage error") }
        catch { #expect(!store.hasPendingDeckChanges && store.snapshot.decks.count == 2) }
    }

    @Test func mergeHandlesMovesReordersAndDecodedSequences() throws {
        var base = Snapshot.starter.decks
        base[0].pads[0].kind = "macro"; base[0].pads[0].value = ""
        base[0].pads[0].steps = [ActionStep()]
        // Decoding regenerates UI step IDs; it must not count as a local edit.
        var local = try JSONDecoder().decode([Deck].self, from: JSONEncoder().encode(base))
        var remote = base
        remote[0].pads[0].steps[0].value = "Ctrl+C"
        local[1].pads.append(local[0].pads.removeFirst())
        local[0].pads.swapAt(0, 1)
        remote[0].pads[0].color = "green"
        let merged = DeckChanges(base: base, decks: local).merged(with: remote)
        #expect(merged[1].pads.last?.steps[0].value == "Ctrl+C")
        #expect(merged[1].pads.last?.color == "green")
        #expect(merged[0].pads.map(\.id) == local[0].pads.map(\.id))
        #expect(Set(merged.flatMap(\.pads).map(\.id)).count == merged.flatMap(\.pads).count)
        #expect(DeckChanges.same(DeckChanges(base: base, decks: local).merged(with: merged), merged))
    }

    @Test func editedDeckSurvivesRemoteDeletionAndLocalDeletionWins() {
        let base = Snapshot.starter.decks
        var local = base; local[0].name = "Keep my edits"
        let restored = DeckChanges(base: base, decks: local).merged(with: [base[1]])
        #expect(restored.first(where: { $0.id == base[0].id })?.pads.count == 6)
        let deleted = DeckChanges(base: base, decks: [base[1]]).merged(with: local)
        #expect(deleted.map(\.id) == [base[1].id])
        let unchanged = DeckChanges(base: base, decks: base).merged(with: [base[1]])
        #expect(unchanged.map(\.id) == [base[1].id])
    }
}
