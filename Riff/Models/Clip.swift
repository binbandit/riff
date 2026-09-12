import Foundation

struct Clip: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var duration: Double
    var editedCopyName: String {
        let suffix = " (edited)"
        var base = name
        while (base + suffix).utf16.count > 60 { base.removeLast() }
        return base + suffix
    }
    var buttonTitle: String {
        var title = name
        while title.utf16.count > 40 { title.removeLast() }
        return title
    }
}
