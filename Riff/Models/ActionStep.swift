import Foundation

struct ActionStep: Codable, Hashable, Identifiable {
    var kind = "hotkey"
    var value = "Ctrl+Shift+M"
    var delayMs = 0
    var id = UUID().uuidString
    enum CodingKeys: String, CodingKey { case kind, value, delayMs }

    static var gameChatMessage: [ActionStep] {
        [
            ActionStep(kind: "hotkey", value: "K"),
            ActionStep(kind: "text", value: "GG", delayMs: 300),
            ActionStep(kind: "hotkey", value: "Enter", delayMs: 100)
        ]
    }
}
