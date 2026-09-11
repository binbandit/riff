import Foundation
import Testing
@testable import RiffProtocol

@MainActor struct SoundDeckBuilderTests {
    @Test func addsInSelectionOrderWithoutChangingOtherActions() throws {
        let snapshot = Snapshot.starter
        let target = snapshot.decks[1]
        let ids = ["red-alert", "nope", "countdown", "nope"]
        let plan = try SoundDeckAddition(snapshot: snapshot, clipIDs: ids, target: .existing(target.id))
        #expect(plan.added.map(\.id) == ["red-alert", "nope", "countdown"])
        #expect(Array(plan.decks[1].pads.prefix(target.pads.count)) == target.pads)
        #expect(plan.decks[0] == snapshot.decks[0])
        #expect(plan.decks[1].pads.suffix(3).map(\.value) == ["red-alert", "nope", "countdown"])
        #expect(Set(plan.decks.flatMap(\.pads).map(\.id)).count == snapshot.decks.flatMap(\.pads).count + 3)
        #expect(snapshot.decks[1].pads == target.pads)
    }
    @Test func skipsDirectButtonsButStillAddsIndependentButtonsForSequenceSounds() throws {
        var snapshot = Snapshot.starter
        snapshot.decks[1].pads = [Pad(title: "Custom callout", icon: "airplane", value: "nope"), Pad(kind: "macro", steps: [ActionStep(kind: "sound", value: "red-alert")])]
        let original = snapshot.decks[1].pads[0]
        let plan = try SoundDeckAddition(snapshot: snapshot, clipIDs: ["nope", "red-alert"], target: .existing(snapshot.decks[1].id))
        #expect(plan.skipped == 1)
        #expect(plan.added.map(\.id) == ["red-alert"])
        #expect(plan.decks[1].pads[0] == original)
    }
    @Test func createsNamedDeckWithSafeTitlesAndIndependentButtons() throws {
        var snapshot = Snapshot.starter
        snapshot.clips[0].name = String(repeating: "✈️", count: 30)
        let plan = try SoundDeckAddition(snapshot: snapshot, clipIDs: [snapshot.clips[0].id], target: .new(id: "pilot", name: "  Pilot calls \n", icon: "airplane"))
        let deck = try #require(plan.decks.last)
        #expect(deck.id == "pilot" && deck.name == "Pilot calls" && deck.icon == "airplane")
        #expect(deck.pads[0].title.utf16.count <= 40)
        #expect(deck.pads[0].kind == "sound" && deck.pads[0].value == snapshot.clips[0].id)
        #expect(!snapshot.decks.flatMap(\.pads).contains { $0.id == deck.pads[0].id })
        #expect(deck.steamAppId.isEmpty)
    }
    @Test func capacityCountsOnlyNewButtonsAndNeverPartiallyAdds() throws {
        var snapshot = Snapshot.starter
        snapshot.decks[1].pads = (0..<47).map { _ in Pad(value: "nope") }
        let target = SoundDeckTarget.existing(snapshot.decks[1].id)
        let fits = try SoundDeckAddition(snapshot: snapshot, clipIDs: ["nope", "red-alert"], target: target)
        #expect(fits.decks[1].pads.count == 48 && fits.skipped == 1)
        #expect(throws: (any Error).self) { try SoundDeckAddition(snapshot: snapshot, clipIDs: ["red-alert", "countdown"], target: target) }
        #expect(snapshot.decks[1].pads.count == 47)
    }
    @Test func rejectsRemovedSoundsAndDecksAndEmptySelection() {
        let snapshot = Snapshot.starter
        #expect(throws: (any Error).self) { try SoundDeckAddition(snapshot: snapshot, clipIDs: ["missing"], target: .existing("soundboard")) }
        #expect(throws: (any Error).self) { try SoundDeckAddition(snapshot: snapshot, clipIDs: ["nope"], target: .existing("missing")) }
        #expect(throws: (any Error).self) { try SoundDeckAddition(snapshot: snapshot, clipIDs: [], target: .existing("soundboard")) }
    }
    @Test func enforcesDeckCountAndUnicodeNameLimits() throws {
        var snapshot = Snapshot.starter
        for name in ["  ", String(repeating: "✈️", count: 21)] {
            #expect(throws: (any Error).self) { try SoundDeckAddition(snapshot: snapshot, clipIDs: ["nope"], target: .new(id: "new", name: name, icon: "waveform")) }
        }
        snapshot.decks += (0..<18).map { _ in Deck() }
        #expect(throws: (any Error).self) { try SoundDeckAddition(snapshot: snapshot, clipIDs: ["nope"], target: .new(id: "new", name: "Memes", icon: "waveform")) }
        let plan = try SoundDeckAddition(snapshot: snapshot, clipIDs: ["nope"], target: .existing(snapshot.decks[1].id))
        #expect(plan.added.count == 1)
    }
}
