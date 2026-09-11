import Foundation

enum SoundScope: String, CaseIterable, Identifiable {
    case all = "All", favorites = "Favorites", deck = "This deck"
    var id: String { rawValue }
}

enum SoundCatalog {
    static func visible(_ clips: [Clip], query: String, scope: SoundScope, favorites: Set<String>, deck: Deck?) -> [Clip] {
        let used = Set((deck?.pads ?? []).flatMap { pad in
            pad.kind == "sound" ? [pad.value] : pad.kind == "macro" ? pad.steps.filter { $0.kind == "sound" }.map(\.value) : []
        })
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return clips.filter { clip in
            (search.isEmpty || clip.name.localizedStandardContains(search)) &&
            (scope != .favorites || favorites.contains(clip.id)) &&
            (scope != .deck || used.contains(clip.id))
        }.sorted { lhs, rhs in
            let comparison = lhs.name.localizedStandardCompare(rhs.name)
            return comparison == .orderedSame ? lhs.id < rhs.id : comparison == .orderedAscending
        }
    }
}
