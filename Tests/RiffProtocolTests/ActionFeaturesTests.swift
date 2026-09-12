import Foundation
import Testing
@testable import RiffProtocol

@MainActor struct ActionFeaturesTests {
    @Test func oldDecksOmitNewFieldsAndNewActionsRoundTrip() throws {
        let legacy = try JSONEncoder().encode(Snapshot.starter)
        let text = String(decoding: legacy, as: UTF8.self)
        #expect(!text.contains("alternateSteps"))
        #expect(!text.contains("linkedAppId"))
        var state = try JSONDecoder().decode(Snapshot.self, from: legacy)
        state.decks[0].linkedAppId = "obs"
        state.decks[0].pads[0] = Pad(kind: "switch", value: "", steps: [ActionStep(kind: "text", value: "First")],
                                    alternateSteps: [ActionStep(kind: "text", value: "Second")])
        state.activeAppId = "obs"
        state.switchState = SoundPlaybackState(sessionId: "test", revision: 2, padIds: [state.decks[0].pads[0].id])
        let decoded = try JSONDecoder().decode(Snapshot.self, from: JSONEncoder().encode(state))
        #expect(decoded.activeAppId == "obs")
        #expect(decoded.decks[0].linkedAppId == "obs")
        #expect(decoded.decks[0].pads[0].alternateSteps?.first?.value == "Second")
        #expect(decoded.switchState == state.switchState)
        let copy = decoded.decks[0].pads[0].duplicated()
        #expect(copy.alternateSteps?.first?.id != decoded.decks[0].pads[0].alternateSteps?.first?.id)
    }

    @Test func smartProfilesPrioritizeFocusedAppPauseEditingAndRespectManualChoice() {
        var state = Snapshot.starter
        state.decks[0].steamAppId = "730"
        state.decks[1].linkedAppId = "obs"
        state.activeGameId = "730"
        state.activeAppId = "obs"
        var profiles = SmartProfiles()
        #expect(profiles.selection(in: state, followApps: true, followGames: true, paused: true) == nil)
        #expect(profiles.selection(in: state, followApps: true, followGames: true, paused: false) == state.decks[1].id)
        // Polling the same context must not undo a manual deck choice.
        #expect(profiles.selection(in: state, followApps: true, followGames: true, paused: false) == nil)
        state.activeAppId = ""
        #expect(profiles.selection(in: state, followApps: true, followGames: true, paused: false) == state.decks[0].id)
        state.activeAppId = "obs"
        #expect(profiles.selection(in: state, followApps: false, followGames: true, paused: false) == nil)
        #expect(profiles.selection(in: state, followApps: true, followGames: true, paused: false) == state.decks[1].id)
        state.activeAppId = "unlinked"
        #expect(profiles.selection(in: state, followApps: true, followGames: false, paused: false) == nil)
    }

    @Test func navigationWorksOfflineAndManualSelectionResetsHistory() async {
        let store = RiffStore(cacheURL: URL.temporaryDirectory.appendingPathComponent(UUID().uuidString), pairing: nil)
        store.snapshot = Snapshot.starter
        store.snapshot.decks.append(Deck(id: "third"))
        await store.trigger(Pad(kind: "deck", value: "everyday"))
        #expect(store.selectedDeckId == "everyday" && store.canGoBack)
        await store.trigger(Pad(kind: "deck", value: "third"))
        await store.trigger(Pad(kind: "back", value: ""))
        #expect(store.selectedDeckId == "everyday" && store.canGoBack)
        await store.trigger(Pad(kind: "back", value: ""))
        #expect(store.selectedDeckId == "soundboard" && !store.canGoBack)
        store.openDeck("third")
        store.selectedDeckId = "everyday"
        #expect(!store.canGoBack)
        store.openDeck("missing")
        #expect(store.selectedDeckId == "everyday" && store.error != nil)
    }

    @Test func navigationSkipsDeletedDecksAndCopiesRelinkSelfNavigation() {
        let store = RiffStore(cacheURL: URL.temporaryDirectory.appendingPathComponent(UUID().uuidString), pairing: nil)
        store.snapshot = Snapshot.starter
        store.snapshot.decks.append(Deck(id: "third"))
        store.openDeck("everyday"); store.openDeck("third")
        store.snapshot.decks.removeAll { $0.id == "everyday" }
        store.goBack()
        #expect(store.selectedDeckId == "soundboard")
        let deck = Deck(id: "source", pads: [Pad(kind: "deck", value: "source")], linkedAppId: "obs")
        let copy = deck.duplicated()
        #expect(copy.linkedAppId == nil && copy.pads[0].value == copy.id)
    }

    @Test func capabilityGatesAndSoundboardModeAgreeWithCompanion() {
        let store = RiffStore(cacheURL: URL.temporaryDirectory.appendingPathComponent(UUID().uuidString), pairing: nil)
        store.snapshot = Snapshot.starter
        store.connected = true
        #expect(!store.availableActionKinds.contains(.actionSwitch))
        store.snapshot.capabilities = ["deck-actions-v1", "smart-profiles-v1"]
        #expect(store.availableActionKinds.contains(.actionSwitch) && store.supportsSmartProfiles)
        store.snapshot.soundboardOnly = true
        for kind in ["deck", "back", "stop", "sound"] { #expect(!store.snapshot.blocksDesktopAction(Pad(kind: kind))) }
        for kind in ["switch", "random", "macro"] { #expect(store.snapshot.blocksDesktopAction(Pad(kind: kind))) }
        #expect(ActionKind.allCases.filter(\.isStep).count == 6)
    }
}
