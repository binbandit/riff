import Foundation
import Testing
@testable import RiffProtocol

@MainActor final class SuggestionTestTransport {
    var started = false
    var client: AISuggestionClient { AISuggestionClient { [self] in try await send($0) } }
    private func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        #expect(request.url?.absoluteString == "https://api.openai.com/v1/responses")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-device-key")
        struct Request: Decodable {
            let input: String
            let text: Text
            struct Text: Decodable { let format: Format }
            struct Format: Decodable { let name: String }
        }
        struct Context: Decodable {
            var titleHint: String?
            var deckName: String?
            var sounds: [Sound]?
            struct Sound: Decodable { let clipId: String }
        }
        let body = try JSONDecoder().decode(Request.self, from: #require(request.httpBody))
        let context = try JSONDecoder().decode(Context.self, from: Data(body.input.utf8))
        let hint = context.titleHint ?? context.deckName ?? ""
        if hint == "hold" {
            started = true
            try await Task.sleep(for: .seconds(30))
        }
        let output: String
        switch body.text.format.name {
        case "button_appearance":
            output = #"{"label":"Air Horn","icon":"speaker.wave.2","color":"orange"}"#
        case "sound_button_appearances":
            var ids = try #require(context.sounds).map(\.clipId)
            if hint == "missing" { ids.removeLast() }
            let buttons = ids.enumerated().reversed().map {
                SoundButtonSuggestion(clipId: $0.element, label: "Sound \($0.offset + 1)", icon: "speaker.wave.2", color: "orange")
            }
            output = String(decoding: try JSONEncoder().encode(SoundSuggestionBatch(buttons: buttons)), as: UTF8.self)
        case "starter_deck":
            output = #"{"name":"Game night","icon":"gamecontroller","summary":"Reactions","buttons":[{"optionId":"option-0","label":"Reaction","icon":"waveform","color":"orange","reason":"A quick reaction."}]}"#
        default: throw RiffError.message("Unexpected AI request")
        }
        struct Response: Encodable {
            let status = "completed"
            let output: [Item]
            struct Item: Encodable { let type = "message"; let content: [Content] }
            struct Content: Encodable { let type = "output_text"; let text: String }
        }
        let data = try JSONEncoder().encode(Response(output: [.init(content: [.init(text: output)])]))
        return (data, HTTPURLResponse(url: request.url!, statusCode: hint == "failure" ? 503 : 200, httpVersion: nil, headerFields: nil)!)
    }
}
