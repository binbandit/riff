import Foundation

struct Clip: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var duration: Double
    var buttonTitle: String {
        var title = name
        while title.utf16.count > 40 { title.removeLast() }
        return title
    }
}
