import Foundation
import Testing
@testable import RiffProtocol

@MainActor struct KeyLogicTests {
    private var pad: Pad { Pad(kind: "text", value: "Tap", doubleTapAction: PadGestureAction(kind: "sound", value: "level-up"), holdAction: PadGestureAction(kind: "deck", value: "soundboard")) }

    @Test func resolvesOnlyTheSelectedActionAndKeepsPlaybackIdentity() throws {
        #expect(pad.resolved(for: .tap)?.value == "Tap")
        #expect(pad.resolved(for: .doubleTap)?.value == "level-up")
        #expect(pad.resolved(for: .hold)?.kind == "deck")
        #expect(Pad().resolved(for: .doubleTap) == nil)
    }

    @Test func legacyJSONOmitsGesturesAndNewBindingsRoundTrip() throws {
        let encoded = try JSONEncoder().encode(Pad())
        #expect(!String(decoding: encoded, as: UTF8.self).contains("holdAction"))
        #expect(try JSONDecoder().decode(Pad.self, from: encoded).hasKeyLogic == false)
        let original = pad
        let decoded = try JSONDecoder().decode(Pad.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
        #expect(decoded.resolved(for: .doubleTap)?.id == original.id)
        #expect(decoded.duplicated().gestureActions == original.gestureActions)
    }

    @Test func sharingRequiresNewFormatAndRelinksGestureDependencies() throws {
        var state = Snapshot.starter
        state.decks[0].pads = [pad]
        let package = try DeckPackage.make(deck: state.decks[0], snapshot: state, grid: GridPreferences())
        #expect(package.schemaVersion == 2)
        #expect(package.dependencies.contains { $0.kind == "sound" && $0.value == "level-up" })
        #expect(package.compatibilityIssue(in: state) != nil)
        state.capabilities = ["key-logic-v1"]
        #expect(package.compatibilityIssue(in: state) == nil)
        let imported = try package.importedDeck(name: "Copy", matches: ["sound:level-up": "nope"], snapshot: state)
        #expect(imported.pads[0].doubleTapAction?.value == "nope")
        #expect(imported.pads[0].holdAction?.value == imported.id)
        var legacy = package; legacy.schemaVersion = 1
        #expect(throws: (any Error).self) { try legacy.validate() }
        var invalid = package; invalid.deck.pads[0].holdAction = PadGestureAction(kind: "macro", value: "")
        #expect(throws: (any Error).self) { try invalid.validate() }
        let copy = state.decks[0].duplicated()
        #expect(copy.pads[0].holdAction?.value == copy.id)
    }

    @Test func offlineMergePreservesIndependentGestureEditsAndChecksReferences() throws {
        var base = Snapshot.starter.decks
        base[0].pads = [pad]
        var local = base, remote = base
        local[0].pads[0].holdAction = PadGestureAction(kind: "back", value: "")
        remote[0].pads[0].doubleTapAction = PadGestureAction(kind: "media", value: "mute")
        remote[0].pads[0].title = "PC title"
        let merged = DeckChanges(base: base, decks: local).merged(with: remote)
        #expect(merged[0].pads[0].holdAction?.kind == "back")
        #expect(merged[0].pads[0].doubleTapAction?.value == "mute")
        #expect(merged[0].pads[0].title == "PC title")
        var bad = base; bad[0].pads[0].holdAction?.value = "missing"
        #expect(throws: (any Error).self) { try DeckChanges.validate(bad, in: .starter) }
        bad = base; bad[0].pads[0].doubleTapAction?.value = "missing"
        #expect(throws: (any Error).self) { try DeckChanges.validate(bad, in: .starter) }
    }

    @Test func connectedGesturesSendOnlyStoredIdentityAndRespectBlockedActions() async throws {
        let folder = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let cache = folder.appendingPathComponent("snapshot.json")
        var state = Snapshot.starter
        state.capabilities = ["key-logic-v1", "soundboard-playback-v1"]
        state.soundboardOnly = true
        let button = Pad(id: "gestures", kind: "sound", value: "level-up", doubleTapAction: PadGestureAction(kind: "sound", value: "nope"), holdAction: PadGestureAction(kind: "text", value: "Must stay blocked"))
        state.decks[0].pads = [button]
        try JSONEncoder().encode(state).write(to: cache)
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/companion_state_server.py").path, cache.path]
        let pipe = Pipe(); process.standardOutput = pipe
        try process.run()
        defer { process.terminate(); process.waitUntilExit() }
        let pairing = try JSONDecoder().decode(Pairing.self, from: pipe.fileHandleForReading.availableData)
        let client = CompanionClient(pairing: pairing)
        let store = RiffStore(cacheURL: cache, pairing: pairing)
        await store.refresh()
        await store.trigger(button)
        await store.trigger(button, gesture: .doubleTap)
        await store.trigger(button, gesture: .hold)
        struct Sent: Decodable { let padId: String; let requestId: String; let gesture: String? }
        let sent: [Sent] = try await client.request("/test/button-triggers")
        #expect(sent.count == 2)
        #expect(sent.allSatisfy { $0.padId == button.id })
        #expect(sent.first?.gesture == nil)
        #expect(sent.last?.gesture == "doubleTap")
        #expect(Set(sent.map(\.requestId)).count == 2)
        #expect(store.error?.contains("Soundboard mode") == true)
    }

    @Test func selectedGestureControlsOfflineNavigationAndSoundboardPolicy() async {
        let store = RiffStore(cacheURL: URL.temporaryDirectory.appendingPathComponent(UUID().uuidString), pairing: nil)
        var button = pad
        button.holdAction?.value = "everyday"
        await store.trigger(button, gesture: .hold)
        #expect(store.selectedDeckId == "everyday")
        store.connected = true; store.snapshot.soundboardOnly = true
        store.snapshot.capabilities = ["key-logic-v1"]
        #expect(store.snapshot.blocksDesktopAction(button))
        #expect(!store.snapshot.blocksDesktopAction(button.resolved(for: .doubleTap)!))
        button.holdAction?.value = "soundboard"
        await store.trigger(button, gesture: .hold)
        #expect(store.selectedDeckId == "soundboard")
        store.snapshot.capabilities = []
        button.holdAction?.value = "everyday"
        await store.trigger(button, gesture: .hold)
        #expect(store.selectedDeckId == "soundboard" && store.error != nil)
        await store.trigger(Pad(), gesture: .hold)
        #expect(store.error == "No action is assigned to this gesture.")
    }
}
