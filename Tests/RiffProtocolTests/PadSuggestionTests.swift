import Foundation
import Testing
@testable import RiffProtocol

@MainActor struct PadSuggestionTests {
    @Test func suggestionsPreserveManualChoicesAndTheAction() throws {
        var pad = Pad(title: "My label", icon: "emoji:🔥", color: "pink", kind: "macro", value: "", steps: [ActionStep()])
        let suggestion = try PadSuggestion(label: "Mute mic", icon: "mic", color: "blue").validated()
        var edits = PadSuggestionEdits()
        edits.label = true; edits.icon = true
        let updated = edits.applying(suggestion, to: pad)
        #expect(updated.title == "My label" && updated.icon == "emoji:🔥" && updated.color == "blue")
        #expect(updated.id == pad.id && updated.kind == pad.kind && updated.value == pad.value && updated.steps == pad.steps)
        edits.color = true
        #expect(edits.allEdited && edits.applying(suggestion, to: pad) == pad)
        pad.color = "green"
        #expect(edits.applying(suggestion, to: pad).color == "green")
    }

    @Test func automaticFieldsCanRefreshForAnotherAction() {
        let edits = PadSuggestionEdits()
        let first = edits.applying(PadSuggestion(label: "First", icon: "mic", color: "blue"), to: Pad())
        let second = edits.applying(PadSuggestion(label: "Second", icon: "flame", color: "orange"), to: first)
        #expect(second.title == "Second" && second.icon == "flame" && second.color == "orange")
    }

    @Test func rejectsInvalidSuggestions() {
        for suggestion in [
            PadSuggestion(label: " ", icon: "mic", color: "blue"),
            PadSuggestion(label: String(repeating: "🔥", count: 21), icon: "mic", color: "blue"),
            PadSuggestion(label: "Test", icon: "unknown.symbol", color: "blue"),
            PadSuggestion(label: "Test", icon: "mic", color: "unknown")
        ] {
            #expect(throws: (any Error).self) { try suggestion.validated() }
        }
    }

    @Test func waitsForUsableActionsAndIgnoresGeneratedAppearance() throws {
        let snapshot = Snapshot.starter
        #expect(PadSuggestionRequest(pad: Pad(value: "missing"), snapshot: snapshot, titleHint: "") == nil)
        #expect(PadSuggestionRequest(pad: Pad(kind: "url", value: "https://"), snapshot: snapshot, titleHint: "") == nil)
        #expect(PadSuggestionRequest(pad: Pad(kind: "macro", value: "", steps: []), snapshot: snapshot, titleHint: "") == nil)
        let pad = Pad(value: snapshot.clips[0].id)
        let request = try #require(PadSuggestionRequest(pad: pad, snapshot: snapshot, titleHint: ""))
        let updated = PadSuggestionEdits().applying(PadSuggestion(label: "Updated", icon: "flame", color: "pink"), to: pad)
        #expect(request == PadSuggestionRequest(pad: updated, snapshot: snapshot, titleHint: ""))
        #expect(request != PadSuggestionRequest(pad: updated, snapshot: snapshot, titleHint: "My sound"))
    }

    @Test func pairedSuggestionsHandleFailuresAndCancelWithoutChangingDecks() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let cache = folder.appendingPathComponent("snapshot.json")
        var state = Snapshot.starter
        state.capabilities = ["pad-suggestions-v1", "pad-suggestions-enabled-v1"]
        try JSONEncoder().encode(state).write(to: cache)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/companion_state_server.py").path, cache.path]
        let pipe = Pipe(); process.standardOutput = pipe
        try process.run()
        defer { process.terminate(); process.waitUntilExit() }
        let pairing = try JSONDecoder().decode(Pairing.self, from: pipe.fileHandleForReading.availableData)
        let client = CompanionClient(pairing: pairing)
        let store = RiffStore(cacheURL: cache, pairing: pairing)
        await store.refresh()
        let pad = Pad(value: state.clips[0].id)
        let request = try #require(PadSuggestionRequest(pad: pad, snapshot: state, titleHint: ""))
        let suggestion = try await store.suggestPadAppearance(request)
        #expect(suggestion.label == "Air Horn")
        #expect(store.snapshot.decks == state.decks && !store.busy)
        let failure = try #require(PadSuggestionRequest(pad: pad, snapshot: state, titleHint: "failure"))
        do {
            _ = try await store.suggestPadAppearance(failure)
            Issue.record("A failed AI request should report an error.")
        } catch { #expect(error.localizedDescription == "AI is unavailable.") }
        #expect(store.error == nil && !store.busy)
        let held = try #require(PadSuggestionRequest(pad: pad, snapshot: state, titleHint: "hold"))
        let pending = Task { try await store.suggestPadAppearance(held) }
        let started: Acknowledgement = try await client.request("/test/suggestion-started")
        #expect(started.ok)
        pending.cancel()
        let _: Acknowledgement = try await client.request("/test/release-suggestion")
        do { _ = try await pending.value; Issue.record("A cancelled request must not return a suggestion.") }
        catch { #expect(error is CancellationError || (error as? URLError)?.code == .cancelled) }
        #expect(store.snapshot.decks == state.decks && !store.busy)
        store.snapshot.capabilities = nil
        #expect(!store.padSuggestionsEnabled)
        do { _ = try await store.suggestPadAppearance(request); Issue.record("Older companions cannot suggest appearances.") }
        catch { #expect(error.localizedDescription.contains("Set up AI suggestions")) }
    }

    @Test func requestsIncludeBothSwitchSidesAndNavigationActions() throws {
        let snapshot = Snapshot.starter
        for kind in ["back", "stop"] {
            #expect(PadSuggestionRequest(pad: Pad(kind: kind, value: ""), snapshot: snapshot, titleHint: "") != nil)
        }
        var pad = Pad(kind: "switch", value: "", steps: [ActionStep()], alternateSteps: [ActionStep(kind: "text", value: "Bye")])
        let first = try #require(PadSuggestionRequest(pad: pad, snapshot: snapshot, titleHint: ""))
        #expect(first.alternateSteps?.first?.value == "Bye")
        pad.alternateSteps?[0].value = "Hello"
        #expect(first != PadSuggestionRequest(pad: pad, snapshot: snapshot, titleHint: ""))
        pad.alternateSteps = []
        #expect(PadSuggestionRequest(pad: pad, snapshot: snapshot, titleHint: "") == nil)
    }
}
