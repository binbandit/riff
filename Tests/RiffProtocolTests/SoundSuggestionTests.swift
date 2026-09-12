import Foundation
import Testing
@testable import RiffProtocol

@MainActor struct SoundSuggestionTests {
    private func suggestion(_ id: String, label: String = "Air Horn") -> SoundButtonSuggestion {
        SoundButtonSuggestion(clipId: id, label: label, icon: "speaker.wave.2", color: "orange")
    }

    @Test func batchRequiresExactlyTheSelectedSounds() throws {
        let batch = SoundSuggestionBatch(buttons: [suggestion("b", label: "Victory"), suggestion("a")])
        let result = try batch.appearances(for: ["a", "b"])
        #expect(result["a"]?.label == "Air Horn" && result["b"]?.label == "Victory")
        for buttons in [[suggestion("a")], [suggestion("a"), suggestion("a")], [suggestion("a"), suggestion("other")], [suggestion("a"), suggestion("b", label: "")]] {
            #expect(throws: (any Error).self) { try SoundSuggestionBatch(buttons: buttons).appearances(for: ["a", "b"]) }
        }
        let ids = (0..<48).map { "sound-\($0)" }
        #expect(try SoundSuggestionBatch(buttons: ids.reversed().map { suggestion($0) }).appearances(for: ids).count == 48)
    }

    @Test func bulkAppearancesPreserveOrderActionsAndExistingButtons() throws {
        var snapshot = Snapshot.starter
        snapshot.clips = [Clip(id: "a", name: "First sound", duration: 1), Clip(id: "b", name: "Second sound", duration: 2)]
        let existing = Pad(title: "Keep", icon: "heart", color: "pink", value: "a")
        snapshot.decks = [Deck(id: "target", pads: [existing])]
        let maliciousAppearance = Pad(title: "Suggested", icon: "flame", color: "green", kind: "url", value: "https://example.com", pinned: true)
        let result = try SoundDeckAddition(snapshot: snapshot, clipIDs: ["b", "a", "b"], target: .existing("target"), appearances: ["a": maliciousAppearance, "b": maliciousAppearance])
        #expect(result.skipped == 1 && result.added.map(\.id) == ["b"])
        #expect(result.decks[0].pads[0] == existing)
        let added = result.decks[0].pads[1]
        #expect(added.title == "Suggested" && added.icon == "flame" && added.color == "green")
        #expect(added.kind == "sound" && added.value == "b" && added.steps.isEmpty && !added.isPinned)
        #expect(added.id != maliciousAppearance.id)
        let new = try SoundDeckAddition(snapshot: snapshot, clipIDs: ["b", "a"], target: .new(id: "new", name: "New", icon: "waveform"), appearances: ["b": maliciousAppearance])
        #expect(new.decks.last?.pads.map(\.value) == ["b", "a"])
        #expect(new.decks.last?.pads.last?.title == "First sound")
    }

    @Test func lateSuggestionsPreserveManualFieldsIncludingEmoji() {
        let base = Pad(value: "sound")
        let suggestion = PadSuggestion(label: "Air Horn", icon: "speaker.wave.2", color: "orange")
        let edits = SoundButtonEdits(label: "My horn", icon: "emoji:🔥")
        let result = edits.applying(to: PadSuggestionEdits().applying(suggestion, to: base))
        #expect(result.title == "My horn" && result.icon == "emoji:🔥" && result.color == "orange")
        #expect(result.value == base.value && result.id == base.id)
        let withoutAI = edits.applying(to: base)
        #expect(withoutAI.title == "My horn" && withoutAI.icon == "emoji:🔥" && withoutAI.color == base.color)
    }
    @Test func pairedBatchHandlesFailureIncompleteResultsAndCancellation() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let cache = folder.appendingPathComponent("snapshot.json")
        var state = Snapshot.starter
        state.capabilities = ["sound-suggestions-v1", "pad-suggestions-enabled-v1"]
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
        let ids = Array(state.clips.prefix(3).map(\.id))
        let request = SoundSuggestionRequest(clipIds: ids, deckName: "Game night", gameId: "730")
        let result = try await store.suggestSoundAppearances(request)
        #expect(result.count == 3 && result[ids[0]]?.label == "Sound 1")
        #expect(store.snapshot.decks == state.decks && !store.busy)
        for name in ["failure", "missing"] {
            do {
                _ = try await store.suggestSoundAppearances(SoundSuggestionRequest(clipIds: ids, deckName: name))
                Issue.record("Failed or incomplete suggestions must be rejected.")
            } catch { #expect(!error.localizedDescription.isEmpty) }
        }
        let pending = Task { try await store.suggestSoundAppearances(SoundSuggestionRequest(clipIds: ids, deckName: "hold")) }
        let started: Acknowledgement = try await client.request("/test/suggestion-started")
        #expect(started.ok)
        pending.cancel()
        let _: Acknowledgement = try await client.request("/test/release-suggestion")
        do { _ = try await pending.value; Issue.record("Cancelled batches must not return appearances.") }
        catch { #expect(error is CancellationError || (error as? URLError)?.code == .cancelled) }
        #expect(store.snapshot.decks == state.decks && !store.busy && store.error == nil)
        store.snapshot.capabilities = ["pad-suggestions-enabled-v1"]
        do { _ = try await store.suggestSoundAppearances(request); Issue.record("Older companions cannot suggest batches.") }
        catch { #expect(error.localizedDescription.contains("updated Windows companion")) }
    }

}
