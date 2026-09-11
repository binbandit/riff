import Testing
@testable import RiffProtocol

@MainActor struct DeckEditingTests {
    @Test func duplicatesEmojiDeckNamesWithinWindowsLimits() {
        let original = Deck(name: String(repeating: "✈️", count: 20), pads: Snapshot.starter.decks[0].pads, steamAppId: "730")
        let copy = original.duplicated()
        #expect(copy.name.utf16.count <= 40)
        #expect(copy.name.hasSuffix(" copy"))
        #expect(copy.id != original.id && copy.steamAppId.isEmpty)
        #expect(Set(copy.pads.map(\.id)).isDisjoint(with: original.pads.map(\.id)))
        #expect(copy.pads.map(\.value) == original.pads.map(\.value))
        #expect(original.name.utf16.count == 40 && original.steamAppId == "730")
    }
    @Test func movesAnExistingButtonWithoutDuplicatingItsAction() throws {
        let snapshot = Snapshot.starter
        var pad = snapshot.decks[0].pads[0]
        pad.kind = "macro"
        pad.steps = [ActionStep(kind: "sound", value: pad.value, delayMs: 200)]
        let updated = try snapshot.decksSaving(pad, in: snapshot.decks[1].id)
        #expect(!updated[0].pads.contains(where: { $0.id == pad.id }))
        #expect(updated[1].pads.last == pad)
        #expect(updated.flatMap(\.pads).count == snapshot.decks.flatMap(\.pads).count)
        #expect(snapshot.decks[0].pads.contains(where: { $0.id == pad.id }))
    }

    @Test func copyingToAnotherDeckKeepsTheOriginal() throws {
        let snapshot = Snapshot.starter
        let original = snapshot.decks[0].pads[0]
        let copy = original.duplicated()
        let updated = try snapshot.decksSaving(copy, in: snapshot.decks[1].id)
        #expect(updated[0].pads.contains(original))
        #expect(updated[1].pads.last == copy)
    }

    @Test func fullDeckRejectsMovesButAllowsEditingExistingButtons() throws {
        var snapshot = Snapshot.starter
        snapshot.decks[1].pads = (0..<48).map { _ in Pad() }
        let moving = snapshot.decks[0].pads[0]
        #expect(throws: (any Error).self) { try snapshot.decksSaving(moving, in: snapshot.decks[1].id) }
        #expect(throws: (any Error).self) { try snapshot.decksSaving(moving, in: "missing") }
        var existing = snapshot.decks[1].pads[0]; existing.title = "Updated"
        let updated = try snapshot.decksSaving(existing, in: snapshot.decks[1].id)
        #expect(updated[1].pads.count == 48 && updated[1].pads[0].title == "Updated")
    }
}
