import Foundation

struct PadSuggestionRequest: Codable, Hashable {
    let kind: String
    let value: String
    let steps: [ActionStep]
    let titleHint: String
    let alternateSteps: [ActionStep]?

    init?(pad: Pad, snapshot: Snapshot, titleHint: String) {
        func ready(_ kind: String, _ value: String) -> Bool {
            switch kind {
            case "sound": snapshot.clips.contains { $0.id == value }
            case "app": snapshot.apps.contains { $0.id == value }
            case "url": URLComponents(string: value).map { ["https", "http"].contains($0.scheme ?? "") && !($0.host ?? "").isEmpty } ?? false
            case "macro", "switch", "random": !pad.steps.isEmpty
            case "deck": snapshot.decks.contains { $0.id == value }
            case "back", "stop": true
            default: !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        }
        let sequence = ActionKind(rawValue: pad.kind)?.isSequence == true
        let groups = pad.kind == "switch" ? [pad.steps, pad.alternateSteps ?? []] : [pad.steps]
        guard titleHint.utf16.count <= 40, ready(pad.kind, pad.value),
              !sequence || groups.allSatisfy({ !$0.isEmpty && $0.allSatisfy { ActionKind(rawValue: $0.kind)?.isStep == true && ready($0.kind, $0.value) } }) else { return nil }
        kind = pad.kind; value = pad.value; steps = sequence ? pad.steps : []; self.titleHint = titleHint
        alternateSteps = pad.kind == "switch" ? pad.alternateSteps : nil
    }
}

struct PadSuggestion: Codable, Equatable {
    let label: String
    let icon: String
    let color: String

    func validated() throws -> Self {
        guard !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, label.utf16.count <= 40,
              PadAppearance.symbols.contains(icon), Palette.colors.contains(color) else {
            throw RiffError.message("AI returned an appearance that Riff cannot use. Try again or choose your own.")
        }
        return self
    }
}

struct PadSuggestionEdits {
    var label = false
    var icon = false
    var color = false
    var allEdited: Bool { label && icon && color }

    func applying(_ suggestion: PadSuggestion, to pad: Pad) -> Pad {
        var result = pad
        if !label { result.title = suggestion.label.trimmingCharacters(in: .whitespacesAndNewlines) }
        if !icon { result.icon = suggestion.icon }
        if !color { result.color = suggestion.color }
        return result
    }
}

enum PadAppearance {
    static let symbols = ["sparkles", "waveform", "theatermasks", "hand.raised", "timer", "circle.circle", "light.beacon.max", "gamecontroller", "bolt", "heart", "star", "speaker.wave.2", "mic", "playpause", "forward.end", "command", "desktopcomputer", "viewfinder", "text.bubble", "globe", "app", "square.stack.3d.up", "speaker.slash", "flame", "airplane", "airplane.departure", "airplane.arrival", "antenna.radiowaves.left.and.right", "face.smiling", "switch.2", "shuffle", "folder", "arrow.uturn.backward", "stop.fill"]
}
