import Foundation

/// The last PC decks and the local edits are saved together with the snapshot.
/// Stable IDs make replay safe even if a successful response was lost.
struct DeckChanges: Codable {
    var base: [Deck]
    var decks: [Deck]

    static func same<T: Encodable>(_ lhs: T, _ rhs: T) -> Bool {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        // ActionStep's UI identity is intentionally absent from its encoded form.
        return (try? encoder.encode(lhs)) == (try? encoder.encode(rhs))
    }

    func merged(with remote: [Deck]) -> [Deck] {
        let originals = Dictionary(uniqueKeysWithValues: base.map { ($0.id, $0) })
        let locals = Dictionary(uniqueKeysWithValues: decks.map { ($0.id, $0) })
        let remotes = Dictionary(uniqueKeysWithValues: remote.map { ($0.id, $0) })
        var result: [String: Deck] = [:]
        for id in Set(locals.keys).union(remotes.keys) {
            let original = originals[id], local = locals[id], pc = remotes[id]
            if original != nil && local == nil { continue } // Explicit local deletion.
            if pc == nil, let original, let local, Self.same(original, local) { continue }
            guard var deck = pc ?? local else { continue }
            if let local {
                if let original, pc != nil {
                    if local.name != original.name { deck.name = local.name }
                    if local.icon != original.icon { deck.icon = local.icon }
                    if local.steamAppId != original.steamAppId { deck.steamAppId = local.steamAppId }
                    if local.linkedAppId != original.linkedAppId { deck.linkedAppId = local.linkedAppId }
                } else { deck = local }
            }
            deck.pads = []; result[id] = deck
        }
        // Merge globally so moving a button between decks never duplicates its ID.
        func pads(_ source: [Deck]) -> [String: (deck: String, pad: Pad)] {
            Dictionary(uniqueKeysWithValues: source.flatMap { deck in deck.pads.map { ($0.id, (deck.id, $0)) } })
        }
        let oldPads = pads(base), localPads = pads(decks), remotePads = pads(remote)
        var mergedPads: [String: [String: Pad]] = [:]
        for id in Set(localPads.keys).union(remotePads.keys) {
            let original = oldPads[id], local = localPads[id], pc = remotePads[id]
            if original != nil && local == nil { continue }
            if pc == nil, let original, let local, remotes[local.deck] != nil,
               original.deck == local.deck, Self.same(original.pad, local.pad) { continue }
            guard let candidate = pc ?? local else { continue }
            var owner = candidate.deck, pad = candidate.pad
            if let local {
                if let original, pc != nil {
                    if local.deck != original.deck { owner = local.deck }
                    if local.pad.title != original.pad.title { pad.title = local.pad.title }
                    if local.pad.icon != original.pad.icon { pad.icon = local.pad.icon }
                    if local.pad.color != original.pad.color { pad.color = local.pad.color }
                    if local.pad.isPinned != original.pad.isPinned { pad.pinned = local.pad.pinned }
                    if local.pad.doubleTapAction != original.pad.doubleTapAction { pad.doubleTapAction = local.pad.doubleTapAction }
                    if local.pad.holdAction != original.pad.holdAction { pad.holdAction = local.pad.holdAction }
                    // Treat an action and both sequences as one unit to avoid mixing action types.
                    var action = original.pad
                    action.kind = local.pad.kind; action.value = local.pad.value; action.loop = local.pad.loop
                    action.steps = local.pad.steps; action.alternateSteps = local.pad.alternateSteps
                    if !Self.same(action, original.pad) {
                        pad.kind = local.pad.kind; pad.value = local.pad.value; pad.loop = local.pad.loop
                        pad.steps = local.pad.steps; pad.alternateSteps = local.pad.alternateSteps
                    }
                } else { owner = local.deck; pad = local.pad }
            }
            guard result[owner] != nil else { continue }
            mergedPads[owner, default: [:]][id] = pad
        }
        for id in Array(result.keys) {
            let available = mergedPads[id] ?? [:]
            let order = Self.order(base: originals[id]?.pads.map(\.id) ?? [],
                                   local: locals[id]?.pads.map(\.id) ?? [],
                                   remote: remotes[id]?.pads.map(\.id) ?? [], available: Set(available.keys))
            result[id]?.pads = order.compactMap { available[$0] }
        }
        return Self.order(base: base.map(\.id), local: decks.map(\.id), remote: remote.map(\.id),
                          available: Set(result.keys)).compactMap { result[$0] }
    }

    private static func order(base: [String], local: [String], remote: [String], available: Set<String>) -> [String] {
        let common = Set(base).intersection(local).intersection(available)
        let reordered = base.filter { common.contains($0) } != local.filter { common.contains($0) }
        var result = (reordered ? local : remote).filter { available.contains($0) }
        let other = reordered ? remote : local
        for (index, id) in other.enumerated() where available.contains(id) && !result.contains(id) {
            if let previous = other[..<index].last(where: { result.contains($0) }), let position = result.firstIndex(of: previous) {
                result.insert(id, at: position + 1)
            } else if let next = other.dropFirst(index + 1).first(where: { result.contains($0) }), let position = result.firstIndex(of: next) {
                result.insert(id, at: position)
            } else { result.append(id) }
        }
        return result
    }

    static func validate(_ decks: [Deck], in snapshot: Snapshot) throws {
        guard (1...20).contains(decks.count) else { throw RiffError.message("Keep between 1 and 20 decks.") }
        var ids = Set<String>(), games = Set<String>(), apps = Set<String>()
        let deckIDs = Set(decks.map(\.id))
        for deck in decks {
            _ = try DeckPackage.make(deck: deck, snapshot: snapshot, grid: GridPreferences())
            guard ids.insert(deck.id).inserted, deck.pads.allSatisfy({ ids.insert($0.id).inserted }) else {
                throw RiffError.message("Deck and button IDs must be unique.")
            }
            guard deck.steamAppId.count <= 12, deck.steamAppId.allSatisfy({ $0.isASCII && $0.isNumber }),
                  deck.steamAppId.isEmpty || games.insert(deck.steamAppId).inserted else {
                throw RiffError.message("Use a valid Steam app ID, linked to only one deck.")
            }
            if let app = deck.linkedAppId, !app.isEmpty {
                guard snapshot.apps.contains(where: { $0.id == app }), apps.insert(app).inserted else {
                    throw RiffError.message("Choose an allowed app that isn't linked to another deck.")
                }
            }
            for pad in deck.pads {
                if pad.kind == "deck", !deckIDs.contains(pad.value) {
                    throw RiffError.message("Remove buttons linking to a deck before deleting it.")
                }
                for (kind, value) in pad.actionReferences {
                    if kind == "deck", !deckIDs.contains(value) { throw RiffError.message("Remove buttons linking to a deck before deleting it.") }
                    if kind == "sound", !snapshot.clips.contains(where: { $0.id == value }) {
                        throw RiffError.message("Choose a sound from the library for \(pad.title).")
                    }
                    if kind == "app", !snapshot.apps.contains(where: { $0.id == value }) {
                        throw RiffError.message("Allow the application for \(pad.title) in the Windows companion first.")
                    }
                }
            }
        }
    }
}
