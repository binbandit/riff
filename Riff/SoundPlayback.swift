import Foundation

enum SoundPlaybackMode: String, CaseIterable, Identifiable {
    case overlap, single
    var id: String { rawValue }
    var label: String { self == .overlap ? "Overlap" : "One at a time" }
}

struct SoundPlaybackState: Decodable, Equatable {
    let sessionId: String
    let revision: Int64
    let padIds: [String]
}

struct SoundPlaybackTracker {
    private(set) var state: SoundPlaybackState?
    var padIDs: Set<String> { Set(state?.padIds ?? []) }
    mutating func accept(_ next: SoundPlaybackState) {
        if let state, state.sessionId == next.sessionId, next.revision < state.revision { return }
        state = next
    }
}
