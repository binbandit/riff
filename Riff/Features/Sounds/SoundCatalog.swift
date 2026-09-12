import Foundation

enum SoundScope: String, CaseIterable, Identifiable {
    case all = "All", favorites = "Favorites", deck = "This deck"
    var id: String { rawValue }
}

enum SoundCatalog {
    static func visible(_ clips: [Clip], query: String, scope: SoundScope, favorites: Set<String>, deck: Deck?) -> [Clip] {
        var used: Set<String> = []
        for pad in deck?.pads ?? [] {
            for action in pad.actionReferences where action.kind == "sound" { used.insert(action.value) }
        }
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

struct SoundGroup: Identifiable {
    let id: String
    let name: String
    let icon: String
    let clips: [Clip]
}

extension SoundCatalog {
    private static let packs = (try? SoundPacks.load()) ?? []
    static func groups(_ clips: [Clip]) -> [SoundGroup] {
        let starterIDs: Set<String> = ["level-up", "plot-twist", "nope", "countdown", "coin-drop", "red-alert"]
        let packIDs = Set(packs.flatMap { $0.sounds.map(\.clipID) })
        var groups = [
            SoundGroup(id: "personal", name: "My sounds", icon: "mic", clips: clips.filter { !packIDs.contains($0.id) && !starterIDs.contains($0.id) }),
            SoundGroup(id: "starter", name: "Riff essentials", icon: "waveform", clips: clips.filter { starterIDs.contains($0.id) })
        ]
        groups += packs.map { pack in
            let ids = Set(pack.sounds.map(\.clipID))
            return SoundGroup(id: pack.id, name: pack.name, icon: pack.icon, clips: clips.filter { ids.contains($0.id) })
        }
        return groups.filter { !$0.clips.isEmpty }
    }
}
