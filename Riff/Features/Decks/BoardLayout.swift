import Foundation

struct DeckPagination {
    let pinned: [Pad]
    let scrolling: [Pad]
    let pageCapacity: Int
    var pageCount: Int { max(1, (scrolling.count + pageCapacity - 1) / pageCapacity) }

    init(pads: [Pad], capacity: Int) {
        let capacity = max(1, capacity)
        // Always reserve a scrolling slot when the deck doesn't fit. Even a 1×1 grid
        // or a deck of entirely pinned buttons must keep every action reachable.
        let pinLimit = pads.count <= capacity ? capacity : capacity - 1
        pinned = Array(pads.filter(\.isPinned).prefix(pinLimit))
        let ids = Set(pinned.map(\.id))
        scrolling = pads.filter { !ids.contains($0.id) }
        pageCapacity = max(1, capacity - pinned.count)
    }

    func buttons(on page: Int) -> [Pad] {
        let start = min(max(0, page), pageCount - 1) * pageCapacity
        return pinned + scrolling.dropFirst(start).prefix(pageCapacity)
    }

    func label(on page: Int) -> String {
        buttons(on: page).dropFirst(pinned.count).first?.title ?? pinned.first?.title ?? "Empty deck"
    }
}

// Remember the first button's position so grid changes keep the same sounds in view.
struct DeckPageMemory {
    private var firstButtons: [String: Int] = [:]

    func page(deckID: String, capacity: Int, padCount: Int) -> Int {
        let capacity = max(1, capacity)
        let lastPage = max(0, padCount - 1) / capacity
        return min(lastPage, (firstButtons[deckID] ?? 0) / capacity)
    }

    mutating func select(_ page: Int, deckID: String, capacity: Int, padCount: Int) {
        let capacity = max(1, capacity)
        let lastPage = max(0, padCount - 1) / capacity
        firstButtons[deckID] = min(lastPage, max(0, page)) * capacity
    }
}

struct GridPreferences: Codable, Equatable {
    var columns = 0
    var rows = 0

    func dimensions(portrait: Bool) -> (columns: Int, rows: Int) {
        (columns == 0 ? (portrait ? 2 : 3) : min(6, max(1, columns)),
         rows == 0 ? (portrait ? 3 : 2) : min(6, max(1, rows)))
    }
}

struct BoardLayout {
    let columns: Int
    let capacity: Int
    let padHeight: CGFloat
    let gridWidth: CGFloat
    let margin: CGFloat
    let gap: CGFloat

    init(size: CGSize, preferences: GridPreferences, playMode: Bool = false) {
        let portrait = size.height > size.width
        let dimensions = preferences.dimensions(portrait: portrait)
        columns = dimensions.columns
        capacity = columns * dimensions.rows
        margin = size.width < 520 ? 20 : portrait ? 48 : 44
        gap = columns > 4 || size.width < 520 ? 12 : 22
        // Keep custom grids usable in small windows by allowing scrolling.
        gridWidth = max(size.width - margin * 2, CGFloat(columns) * 110 + gap * CGFloat(columns - 1))
        let width = (gridWidth - gap * CGFloat(columns - 1)) / CGFloat(columns)
        let chromeHeight: CGFloat = playMode ? 168 : 264
        let height = (size.height - chromeHeight - gap * CGFloat(dimensions.rows - 1)) / CGFloat(dimensions.rows)
        padHeight = max(110, min(width * 0.96, height))
    }
}
