import Foundation

struct Deck: Codable, Identifiable, Hashable {
    var id = UUID().uuidString
    var name = "New deck"
    var icon = "square.grid.2x2"
    var pads: [Pad] = []
    var steamAppId = ""
    func duplicated() -> Deck {
        var copy = self
        copy.id = UUID().uuidString
        copy.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        while copy.name.utf16.count > 35 { copy.name.removeLast() }
        copy.name += " copy"
        copy.steamAppId = ""
        copy.pads = pads.map { pad in
            var next = pad
            next.id = UUID().uuidString
            return next
        }
        return copy
    }
}
