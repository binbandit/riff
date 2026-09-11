import Foundation

struct ActionStep: Codable, Hashable, Identifiable {
    var kind = "hotkey"
    var value = "Ctrl+Shift+M"
    var delayMs = 0
    var id = UUID().uuidString
    enum CodingKeys: String, CodingKey { case kind, value, delayMs }
}
