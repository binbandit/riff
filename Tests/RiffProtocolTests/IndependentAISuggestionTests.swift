import Foundation
import Testing
@testable import RiffProtocol

@MainActor struct IndependentAISuggestionTests {
    private func response(_ output: String, status: String = "completed", httpStatus: Int = 200) throws -> (Data, URLResponse) {
        struct Response: Encodable {
            let status: String
            let output: [Item]
            struct Item: Encodable { let type = "message"; let content: [Content] }
            struct Content: Encodable { let type = "output_text"; let text: String }
        }
        return (try JSONEncoder().encode(Response(status: status, output: [.init(content: [.init(text: output)])])),
                HTTPURLResponse(url: URL(string: "https://api.openai.com/v1/responses")!, statusCode: httpStatus, httpVersion: nil, headerFields: nil)!)
    }
    @Test func unpairedIPadSuggestsAllThreeKindsAndSavesADeck() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var names: [String] = []
        let client = AISuggestionClient { request in
            #expect(request.url?.absoluteString == "https://api.openai.com/v1/responses")
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-device-key")
            struct Request: Decodable {
                let store: Bool; let model: String; let input: String; let text: Text
                struct Text: Decodable { let format: Format }
                struct Format: Decodable { let name: String; let strict: Bool }
            }
            let body = try JSONDecoder().decode(Request.self, from: #require(request.httpBody))
            #expect(!body.store && body.text.format.strict && body.model == "gpt-5.6-luna")
            #expect(!body.input.contains("test-device-key"))
            names.append(body.text.format.name)
            switch body.text.format.name {
            case "button_appearance":
                return try response(#"{"label":"Level up","icon":"star","color":"orange"}"#)
            case "sound_button_appearances":
                return try response(#"{"buttons":[{"clipId":"level-up","label":"Victory","icon":"star","color":"green"}]}"#)
            case "starter_deck":
                return try response(#"{"name":"Game night","icon":"gamecontroller","summary":"Sounds for your game.","buttons":[{"optionId":"option-0","label":"First sound","icon":"waveform","color":"orange","reason":"A familiar sound."}]}"#)
            default: throw RiffError.message("Unexpected AI request")
            }
        }
        let store = RiffStore(cacheURL: folder.appendingPathComponent("state.json"), pairing: nil, aiKey: "test-device-key", aiSuggestions: client)
        #expect(!store.connected && !store.paired && store.padSuggestionsEnabled)
        #expect(store.supportsPadSuggestions && store.supportsSoundSuggestions && store.supportsDeckSuggestions)
        let original = store.snapshot.decks
        let pad = try #require(PadSuggestionRequest(pad: Pad(value: "level-up"), snapshot: store.snapshot, titleHint: ""))
        #expect(try await store.suggestPadAppearance(pad).icon == "star")
        let sounds = try await store.suggestSoundAppearances(.init(clipIds: ["level-up"], deckName: "Game night"))
        #expect(sounds["level-up"]?.label == "Victory")
        let suggestion = try await store.suggestDeck(.init(gameId: "", appId: "", name: "Game night", intent: ""))
        #expect(store.snapshot.decks == original)
        let deck = Deck(id: UUID().uuidString, name: suggestion.name, icon: suggestion.icon, pads: [], steamAppId: "")
        try await store.createSuggestedDeck(deck, buttons: suggestion.buttons)
        #expect(store.snapshot.decks.last?.pads.first?.value == store.snapshot.clips.first?.id)
        #expect(store.selectedDeckId == deck.id && !store.connected)
        let reloaded = RiffStore(cacheURL: folder.appendingPathComponent("state.json"), pairing: nil)
        #expect(reloaded.snapshot.decks.last == store.snapshot.decks.last)
        #expect(names == ["button_appearance", "sound_button_appearances", "starter_deck"])
        #expect(!reloaded.hasDeviceAIKey && !reloaded.padSuggestionsEnabled)
    }
    @Test func directRequestsRejectFailuresIncompleteAndInvalidResults() async throws {
        let snapshot = Snapshot.starter
        let request = try #require(PadSuggestionRequest(pad: Pad(), snapshot: snapshot, titleHint: ""))
        for (http, status, output) in [(401, "completed", "{}"), (429, "completed", "{}"), (503, "completed", "{}"),
                                      (200, "incomplete", "{}"), (200, "completed", "{}"),
                                      (200, "completed", #"{"label":"Test","icon":"invented","color":"orange"}"#)] {
            let client = AISuggestionClient { _ in try response(output, status: status, httpStatus: http) }
            await #expect(throws: (any Error).self) { try await client.pad(request, snapshot: snapshot, key: "test-key") }
        }
        let cancelled = AISuggestionClient { _ in
            throw CancellationError()
        }
        await #expect(throws: CancellationError.self) { try await cancelled.pad(request, snapshot: snapshot, key: "test-key") }
    }
    @Test func contextRemovesURLSecretsAndUsesNames() throws {
        let snapshot = Snapshot.starter
        let request = try #require(PadSuggestionRequest(pad: Pad(kind: "url", value: "https://user:password@example.com/watch?token=secret#fragment"), snapshot: snapshot, titleHint: "Example"))
        let context = try AISuggestionClient.padContext(request, snapshot: snapshot)
        #expect(context.actions == ["Open website: example.com/watch"])
        let sound = try #require(PadSuggestionRequest(pad: Pad(value: "level-up"), snapshot: snapshot, titleHint: ""))
        #expect(try AISuggestionClient.padContext(sound, snapshot: snapshot).actions == ["Play sound: Level up"])
    }
    @Test func deckChoicesCannotInventOrRepeatActionsAndRespectSoundboardMode() throws {
        var snapshot = Snapshot.starter; snapshot.soundboardOnly = true
        let options = AISuggestionClient.deckOptions(snapshot)
        #expect(options.allSatisfy { ["sound", "stop"].contains($0.pad.kind) })
        for ids in [["invented"], ["option-0", "option-0"]] {
            let proposal = AISuggestionClient.DeckProposal(name: "Deck", icon: "waveform", summary: "Sounds", buttons: ids.map {
                .init(optionId: $0, label: "Sound", icon: "waveform", color: "orange", reason: "Test")
            })
            #expect(throws: (any Error).self) { try proposal.resolved(options: options) }
        }
    }
    @Test func rejectsInvalidKeysBeforeSaving() throws {
        #expect(try AIKeyVault.validated("  test-device-key\n") == "test-device-key")
        for key in ["", "short", "key with spaces", "test-key\u{0}hidden", String(repeating: "a", count: 1025)] {
            #expect(throws: (any Error).self) { try AIKeyVault.validated(key) }
        }
    }
}
