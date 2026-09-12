import Foundation
import Testing
@testable import RiffProtocol

@MainActor struct PinnedPageTests {
    @Test func pinsRepeatInStableSlotsAndOrdinaryActionsAppearExactlyOnce() {
        var pads = (0..<13).map { Pad(id: "\($0)", title: "Button \($0)") }
        pads[2].pinned = true; pads[9].pinned = true
        let pagination = DeckPagination(pads: pads, capacity: 6)
        #expect(pagination.pageCount == 3 && pagination.pageCapacity == 4)
        #expect(pagination.buttons(on: 0).map(\.id) == ["2", "9", "0", "1", "3", "4"])
        #expect(pagination.buttons(on: 2).map(\.id) == ["2", "9", "10", "11", "12"])
        #expect(pagination.label(on: 1) == "Button 5")
    }

    @Test func everyActionRemainsReachableAcrossGridSizesAndPinCounts() {
        for count in [0, 1, 6, 13, 48] {
            for pinCount in 0...count {
                let pads = (0..<count).map { Pad(id: "\($0)", pinned: $0 < pinCount ? true : nil) }
                for capacity in 1...36 {
                    let pagination = DeckPagination(pads: pads, capacity: capacity)
                    let pages = (0..<pagination.pageCount).map { pagination.buttons(on: $0) }
                    #expect(Set(pages.flatMap { $0.map(\.id) }) == Set(pads.map(\.id)))
                    #expect(pages.allSatisfy { $0.count <= capacity && Set($0.map(\.id)).count == $0.count })
                    for page in pages { #expect(Array(page.prefix(pagination.pinned.count)) == pagination.pinned) }
                    #expect(pages.flatMap { $0.dropFirst(pagination.pinned.count) }.map(\.id) == pagination.scrolling.map(\.id))
                }
            }
        }
    }

    @Test func pageMemoryWorksWithPinnedSlotsAndClampsAfterRemoval() {
        var pads = (0..<13).map { Pad(id: "\($0)", pinned: $0 == 0 ? true : nil) }
        var pagination = DeckPagination(pads: pads, capacity: 6)
        var memory = DeckPageMemory()
        memory.select(2, deckID: "deck", capacity: pagination.pageCapacity, padCount: pagination.scrolling.count)
        #expect(memory.page(deckID: "deck", capacity: 5, padCount: 12) == 2)
        pads.removeLast(7); pagination = DeckPagination(pads: pads, capacity: 6)
        #expect(memory.page(deckID: "deck", capacity: pagination.pageCapacity, padCount: pagination.scrolling.count) == 0)
        #expect(pagination.buttons(on: 99).count == 6)
        #expect(DeckPagination(pads: [], capacity: 0).buttons(on: -4).isEmpty)
    }

    @Test func pinsSurviveCopyingAndOlderJSONStaysCompatible() throws {
        let original = Pad(pinned: true)
        #expect(original.duplicated().isPinned)
        let decoded = try JSONDecoder().decode(Pad.self, from: JSONEncoder().encode(original))
        #expect(decoded.isPinned)
        let legacy = Pad()
        let data = try JSONEncoder().encode(legacy)
        #expect(!String(decoding: data, as: UTF8.self).contains("pinned"))
        #expect(try JSONDecoder().decode(Pad.self, from: data).isPinned == false)
    }
}
