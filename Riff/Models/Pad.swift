import Foundation
import SwiftUI

struct Pad: Codable, Identifiable, Hashable {
    var id = UUID().uuidString
    var title = "New button"
    var icon = "sparkles"
    var color = "orange"
    var kind = "sound"
    var value = "level-up"
    var steps: [ActionStep] = []
    var alternateSteps: [ActionStep]? = nil
    var pinned: Bool? = nil
    var doubleTapAction: PadGestureAction? = nil
    var holdAction: PadGestureAction? = nil
    var hasKeyLogic: Bool { doubleTapAction != nil || holdAction != nil }
    var gestureActions: [PadGestureAction] { [doubleTapAction, holdAction].compactMap { $0 } }
    var actionReferences: [(kind: String, value: String)] {
        [(kind, value)] + (steps + (alternateSteps ?? [])).map { ($0.kind, $0.value) } + gestureActions.map { ($0.kind, $0.value) }
    }
    func resolved(for gesture: PadGesture) -> Pad? {
        if gesture == .tap { return self }
        guard let action = gesture == .doubleTap ? doubleTapAction : holdAction else { return nil }
        var result = self
        result.kind = action.kind; result.value = action.value
        result.steps = []; result.alternateSteps = nil
        result.doubleTapAction = nil; result.holdAction = nil
        return result
    }
    var isPinned: Bool { pinned == true }
    var tint: Color { Palette.color(color) }
    var typeName: String { ActionKind(rawValue: kind)?.label ?? "Action" }
    func duplicated() -> Pad {
        var copy = self
        copy.id = UUID().uuidString
        // Leave room for the suffix within the companion's UTF-16 title limit.
        while copy.title.utf16.count > 33 { copy.title.removeLast() }
        copy.title += " (copy)"
        copy.steps = steps.map { step in
            var next = step; next.id = UUID().uuidString; return next
        }
        copy.alternateSteps = alternateSteps?.map { step in
            var next = step; next.id = UUID().uuidString; return next
        }
        return copy
    }
}

// Secondary gestures are single actions, never recursive action containers.
struct PadGestureAction: Codable, Hashable {
    var kind = "media"
    var value = "next"
}

enum PadGesture: String, CaseIterable, Identifiable {
    case tap, doubleTap, hold
    var id: String { rawValue }
    var label: String {
        switch self { case .tap: "Tap"; case .doubleTap: "Double-tap"; case .hold: "Hold" }
    }
}
