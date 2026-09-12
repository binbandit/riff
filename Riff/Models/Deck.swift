import Foundation

struct Deck: Codable, Identifiable, Hashable {
    var id = UUID().uuidString
    var name = "New deck"
    var icon = "square.grid.2x2"
    var pads: [Pad] = []
    var steamAppId = ""
    var linkedAppId: String? = nil
    func duplicated() -> Deck {
        var copy = self
        copy.id = UUID().uuidString
        copy.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        while copy.name.utf16.count > 35 { copy.name.removeLast() }
        copy.name += " copy"
        copy.steamAppId = ""
        copy.linkedAppId = nil
        copy.pads = pads.map { pad in
            var next = pad
            next.id = UUID().uuidString
            if next.kind == "deck", next.value == id { next.value = copy.id }
            if next.doubleTapAction?.kind == "deck", next.doubleTapAction?.value == id { next.doubleTapAction?.value = copy.id }
            if next.holdAction?.kind == "deck", next.holdAction?.value == id { next.holdAction?.value = copy.id }
            return next
        }
        return copy
    }
}
