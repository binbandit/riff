import Foundation

struct DeckDependency: Codable, Hashable, Identifiable {
    var kind: String
    var value: String
    var name: String
    var id: String { "\(kind):\(value)" }
    var label: String { kind == "sound" ? "Sound" : kind == "app" ? "Application" : "Deck" }

    func options(in snapshot: Snapshot) -> [(id: String, name: String)] {
        switch kind {
        case "sound": snapshot.clips.map { ($0.id, $0.name) }
        case "app": snapshot.apps.map { ($0.id, $0.name) }
        case "deck": snapshot.decks.map { ($0.id, $0.name) }
        default: []
        }
    }
}

// A portable layout, deliberately separate from companion state and pairing data.
// Resources are relinked during import; files and app permissions are not transferred.
struct DeckPackage: Codable {
    static let maximumBytes = 8 * 1024 * 1024
    var format = "riff-layout"
    var schemaVersion = 1
    var content = "deck"
    var deck: Deck
    var grid: GridPreferences
    var dependencies: [DeckDependency]

    static func make(deck source: Deck, snapshot: Snapshot, grid: GridPreferences, button: Pad? = nil) throws -> Self {
        var deck = source
        deck.steamAppId = ""; deck.linkedAppId = nil
        if let button {
            // Navigation from a shared button still references the original deck.
            deck.id = UUID().uuidString; deck.name = button.title; deck.pads = [button]
        }
        var package = Self(content: button == nil ? "deck" : "button", deck: deck, grid: grid, dependencies: [])
        if deck.pads.contains(where: \.hasKeyLogic) { package.schemaVersion = 2 }
        if deck.pads.contains(where: { $0.loop == true }) { package.schemaVersion = 3 }
        package.dependencies = package.references.map { kind, value in
            let name: String?
            switch kind {
            case "sound": name = snapshot.clips.first { $0.id == value }?.name
            case "app": name = snapshot.apps.first { $0.id == value }?.name
            default: name = snapshot.decks.first { $0.id == value }?.name
            }
            return DeckDependency(kind: kind, value: value, name: name ?? value)
        }.sorted { $0.id < $1.id }
        try package.validate()
        return package
    }

    static func read(_ data: Data) throws -> Self {
        guard data.count <= maximumBytes else { throw RiffError.message("Choose a Riff layout smaller than 8 MB.") }
        let package: Self
        do { package = try JSONDecoder().decode(Self.self, from: data) }
        catch { throw RiffError.message("This isn't a readable Riff layout. Choose a file exported by Riff.") }
        try package.validate()
        return package
    }

    func encoded() throws -> Data {
        try validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        guard data.count <= Self.maximumBytes else { throw RiffError.message("This layout is too large to share. Share individual buttons instead.") }
        return data
    }

    private var references: [(kind: String, value: String)] {
        var result: [(kind: String, value: String)] = []
        var seen: Set<String> = []
        func add(_ kind: String, _ value: String) {
            guard ["sound", "app", "deck"].contains(kind), !(kind == "deck" && value == deck.id),
                  seen.insert("\(kind):\(value)").inserted else { return }
            result.append((kind, value))
        }
        for pad in deck.pads {
            for action in pad.actionReferences { add(action.kind, action.value) }
        }
        return result
    }

    func validate() throws {
        guard format == "riff-layout", [1, 2, 3].contains(schemaVersion), ["deck", "button"].contains(content) else {
            throw RiffError.message("This layout format isn't supported. Update Riff or export it again from a compatible version.")
        }
        func check(_ text: String, limit: Int, label: String) throws {
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.utf16.count <= limit else {
                throw RiffError.message("\(label) must contain 1–\(limit) characters.")
            }
        }
        try check(deck.id, limit: 80, label: "Deck ID")
        try check(deck.name, limit: 40, label: "Deck name")
        try check(deck.icon, limit: 80, label: "Deck icon")
        guard deck.pads.count <= 48, content != "button" || deck.pads.count == 1,
              (0...6).contains(grid.columns), (0...6).contains(grid.rows) else {
            throw RiffError.message("This layout has an invalid grid or too many buttons.")
        }
        var ids: Set<String> = [deck.id]
        func checkAction(_ kind: String, _ value: String, step: Bool = false) throws {
            guard let action = ActionKind(rawValue: kind), !step || action.isStep else {
                throw RiffError.message("This layout contains an unsupported action: \(kind.prefix(60)).")
            }
            switch action {
            case .sound, .app, .deck: try check(value, limit: 80, label: "Resource ID")
            case .text: try check(value, limit: 2000, label: "Text")
            case .hotkey: try check(value, limit: 100, label: "Shortcut")
            case .url:
                guard value.utf16.count <= 2048, let url = URL(string: value),
                      ["http", "https"].contains(url.scheme?.lowercased() ?? ""), let host = url.host, !host.isEmpty else {
                    throw RiffError.message("Website actions must use a full http or https address.")
                }
            case .media:
                guard ["playPause", "next", "previous", "volumeUp", "volumeDown", "mute"].contains(value) else {
                    throw RiffError.message("This layout contains an unknown media control.")
                }
            default:
                guard value.utf16.count <= 2048 else { throw RiffError.message("An action value is too long.") }
            }
        }
        func checkSteps(_ steps: [ActionStep]) throws {
            guard (1...20).contains(steps.count), steps.allSatisfy({ (0...5000).contains($0.delayMs) }),
                  steps.reduce(0, { $0 + $1.delayMs }) <= 30000 else {
                throw RiffError.message("Sequences need 1–20 steps, delays of 0–5 seconds, and no more than 30 seconds of total delays.")
            }
            for step in steps { try checkAction(step.kind, step.value, step: true) }
        }
        for pad in deck.pads {
            try check(pad.id, limit: 80, label: "Button ID")
            guard ids.insert(pad.id).inserted else { throw RiffError.message("This layout contains duplicate button IDs.") }
            try check(pad.title, limit: 40, label: "Button name")
            try check(pad.icon, limit: 80, label: "Button icon")
            guard Palette.colors.contains(pad.color) else { throw RiffError.message("This layout contains an unknown button color.") }
            guard !pad.hasKeyLogic || schemaVersion >= 2 else { throw RiffError.message("Gesture actions require layout format 2.") }
            guard pad.loop != true || schemaVersion >= 3 else { throw RiffError.message("Looping sounds require layout format 3.") }
            for action in pad.gestureActions {
                guard ActionKind(rawValue: action.kind)?.isGestureAction == true else { throw RiffError.message("Double-tap and hold must use a single action.") }
                try checkAction(action.kind, action.value)
            }
            try checkAction(pad.kind, pad.value)
            if ActionKind(rawValue: pad.kind)?.isSequence == true { try checkSteps(pad.steps) }
            else if !pad.steps.isEmpty { throw RiffError.message("Only sequence and random actions can contain steps.") }
            if pad.kind == "switch" { try checkSteps(pad.alternateSteps ?? []) }
            else if !(pad.alternateSteps ?? []).isEmpty { throw RiffError.message("Only action switches can have a second sequence.") }
        }
        var dependencyIDs: Set<String> = []
        guard dependencies.count <= 2000 else { throw RiffError.message("This layout references too many resources.") }
        for dependency in dependencies {
            guard ["sound", "app", "deck"].contains(dependency.kind), dependencyIDs.insert(dependency.id).inserted else {
                throw RiffError.message("This layout contains invalid or duplicate resources.")
            }
            try check(dependency.value, limit: 80, label: "Resource ID")
            try check(dependency.name, limit: 260, label: "Resource name")
        }
        guard dependencyIDs == Set(references.map { "\($0.kind):\($0.value)" }) else {
            throw RiffError.message("This layout's resource list does not match its actions.")
        }
    }

    func suggestedMatches(in snapshot: Snapshot) -> [String: String] {
        var matches: [String: String] = [:]
        for dependency in dependencies {
            let options = dependency.options(in: snapshot)
            if let exact = options.first(where: { $0.id == dependency.value && $0.name == dependency.name }) {
                matches[dependency.id] = exact.id
            } else {
                let named = options.filter { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == dependency.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                if named.count == 1 { matches[dependency.id] = named[0].id }
            }
        }
        return matches
    }

    func missingMatches(_ matches: [String: String], in snapshot: Snapshot) -> [DeckDependency] {
        dependencies.filter { dependency in
            !dependency.options(in: snapshot).contains { $0.id == matches[dependency.id] }
        }
    }

    func compatibilityIssue(in snapshot: Snapshot) -> String? {
        if deck.pads.contains(where: { $0.loop == true }), snapshot.capabilities?.contains("soundboard-loop-v1") != true {
            return "Update the Windows companion to loop sounds."
        }
        if deck.pads.contains(where: \.hasKeyLogic), snapshot.capabilities?.contains("key-logic-v1") != true {
            return "Update the Windows companion to use double-tap and hold actions."
        }
        if deck.pads.contains(where: { ActionKind(rawValue: $0.kind)?.needsDeckActions == true }),
           snapshot.capabilities?.contains("deck-actions-v1") != true {
            return "Update the Windows companion to import these control actions."
        }
        if deck.pads.contains(where: \.isPinned), snapshot.capabilities?.contains("pinned-pads-v1") != true {
            return "Update the Windows companion to import pinned buttons."
        }
        return nil
    }

    func importedDeck(name: String, into targetID: String? = nil, matches: [String: String], snapshot: Snapshot, newDeckID: String = UUID().uuidString, buttonIDs: [String: String] = [:], checkCompatibility: Bool = true) throws -> Deck {
        try validate()
        if checkCompatibility, let issue = compatibilityIssue(in: snapshot) { throw RiffError.message(issue) }
        guard missingMatches(matches, in: snapshot).isEmpty else { throw RiffError.message("Choose a matching item for every sound, app, and linked deck.") }
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, cleanName.utf16.count <= 40 else { throw RiffError.message("Use a deck name of 1–40 characters.") }
        let freshIDs = deck.pads.map { buttonIDs[$0.id] ?? UUID().uuidString }
        let existingIDs = Set(snapshot.decks.flatMap { [$0.id] + $0.pads.map(\.id) })
        guard Set(freshIDs).count == freshIDs.count, Set(freshIDs).isDisjoint(with: existingIDs),
              !freshIDs.contains(newDeckID), targetID != nil || !existingIDs.contains(newDeckID) else {
            throw RiffError.message("Buttons from this import already exist. Check your decks before importing again.")
        }
        var result: Deck
        if let targetID {
            guard let target = snapshot.decks.first(where: { $0.id == targetID }), target.pads.count + deck.pads.count <= 48 else {
                throw RiffError.message("Choose an existing deck with enough room for these buttons.")
            }
            result = target
        } else {
            guard snapshot.decks.count < 20 else { throw RiffError.message("You have 20 decks. Choose an existing deck or remove one first.") }
            result = Deck(id: newDeckID, name: cleanName, icon: deck.icon)
        }
        let destinationID = result.id
        func remap(_ kind: String, _ value: String) -> String {
            if kind == "deck", value == deck.id { return destinationID }
            return matches["\(kind):\(value)"] ?? value
        }
        func steps(_ source: [ActionStep]) -> [ActionStep] {
            source.map { ActionStep(kind: $0.kind, value: remap($0.kind, $0.value), delayMs: $0.delayMs) }
        }
        result.pads += deck.pads.enumerated().map { index, source in
            var pad = source
            pad.id = freshIDs[index]
            pad.value = remap(source.kind, source.value)
            pad.steps = steps(source.steps)
            pad.alternateSteps = source.kind == "switch" ? steps(source.alternateSteps ?? []) : nil
            pad.doubleTapAction = source.doubleTapAction.map { PadGestureAction(kind: $0.kind, value: remap($0.kind, $0.value)) }
            pad.holdAction = source.holdAction.map { PadGestureAction(kind: $0.kind, value: remap($0.kind, $0.value)) }
            pad.pinned = source.isPinned ? true : nil
            return pad
        }
        return result
    }

    func actionDescription(kind: String, value: String) -> String {
        if kind == "deck", value == deck.id { return "This imported deck" }
        return dependencies.first { $0.kind == kind && $0.value == value }?.name ?? value
    }
}
