import Foundation
import Testing
@testable import RiffProtocol

@MainActor struct ProtocolTests {
    let token = String(repeating: "a", count: 64)
    let fingerprint = String(repeating: "b", count: 64)
    var link: String { "riff://connect?host=192.168.1.10&port=49321&token=\(token)&fp=\(fingerprint)" }

    @Test func duplicateKeepsActionsAndHasIndependentIdentity() {
        let original = Pad(title: String(repeating: "✈️", count: 20), kind: "macro", steps: [ActionStep()])
        let copy = original.duplicated()
        #expect(copy.id != original.id)
        #expect(copy.title.utf16.count <= 40)
        #expect(copy.title.hasSuffix(" (copy)"))
        #expect(copy.kind == original.kind && copy.value == original.value)
        #expect(copy.steps[0].id != original.steps[0].id)
        #expect(copy.steps[0].kind == original.steps[0].kind)
        #expect(copy.steps[0].value == original.steps[0].value)
        #expect(copy.steps[0].delayMs == original.steps[0].delayMs)
        let clip = Clip(id: "pilot", name: String(repeating: "✈️", count: 20), duration: 2)
        #expect(clip.buttonTitle.utf16.count <= 40)
    }
    @Test func acceptsPairingFromCompanion() throws {
        let pairing = try Pairing.parse(" \n" + link + "\n")
        #expect(pairing.host == "192.168.1.10")
        #expect(pairing.port == 49321)
        #expect(pairing.token == token)
        #expect(pairing.fingerprint == fingerprint)
    }
    @Test func rejectsTruncatedAndUntrustedLinks() {
        let bad = ["https://example.com", "riff://connect?host=127.0.0.1", link.replacingOccurrences(of: "49321", with: "0"), link.replacingOccurrences(of: "192.168.1.10", with: "evil.com/path"), link.replacingOccurrences(of: token, with: "short"), link.replacingOccurrences(of: fingerprint, with: String(repeating: "z", count: 64))]
        for value in bad { #expect(throws: (any Error).self) { try Pairing.parse(value) } }
    }
    @Test func snapshotRoundTripKeepsGameLinksAndActions() throws {
        var snapshot = Snapshot.starter
        snapshot.decks[0].steamAppId = "730"
        snapshot.decks[0].pads.swapAt(0, 3)
        snapshot.decks[0].pads[0].kind = "macro"
        snapshot.decks[0].pads[0].steps = [ActionStep()]
        let data = try JSONEncoder().encode(snapshot)
        let next = try JSONDecoder().decode(Snapshot.self, from: data)
        #expect(next.decks[0].steamAppId == "730")
        #expect(next.decks[0].pads[3].id == "level-up-pad")
        #expect(next.decks[0].pads[3].value == "level-up")
        #expect(next.decks.flatMap(\.pads).count == 12)
        let stepData = try JSONEncoder().encode(next.decks[0].pads[0].steps[0])
        let fields = try #require(JSONSerialization.jsonObject(with: stepData) as? [String: Any])
        #expect(Set(fields.keys) == Set(["kind", "value", "delayMs"]))
    }
    @Test func starterSoundsResolveToLibrary() {
        let state = Snapshot.starter
        let clipIds = Set(state.clips.map(\.id))
        #expect(state.decks.flatMap(\.pads).filter { $0.kind == "sound" }.allSatisfy { clipIds.contains($0.value) })
    }
}
