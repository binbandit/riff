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
        return copy
    }
}
