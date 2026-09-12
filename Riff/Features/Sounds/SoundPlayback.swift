import Foundation
import AVFoundation

enum SoundPlaybackMode: String, CaseIterable, Identifiable {
    case overlap, single, queue
    var id: String { rawValue }
    var label: String {
        switch self {
        case .overlap: "Overlap"
        case .single: "One at a time"
        case .queue: "Queue"
        }
    }
    var explanation: String {
        switch self {
        case .overlap: "Different sounds can play together. Tap a playing button again to stop just that sound."
        case .single: "Each new sound stops the previous one. Tap a playing button again to stop it."
        case .queue: "Sounds play in the order you tap them. Tap a waiting sound to remove it, or a playing sound to skip it. Stop all clears the queue."
        }
    }
}

struct SoundPlaybackState: Codable, Equatable {
    let sessionId: String
    let revision: Int64
    let padIds: [String]
    var queuedPadIds: [String]? = nil
}

struct SoundPlaybackTracker {
    private(set) var state: SoundPlaybackState?
    var padIDs: Set<String> { Set(state?.padIds ?? []) }
    var queuedPadIDs: [String] { state?.queuedPadIds ?? [] }
    mutating func accept(_ next: SoundPlaybackState) {
        if let state, state.sessionId == next.sessionId, next.revision < state.revision { return }
        state = next
    }
}

final class SoundPlaybackObserver: NSObject, AVAudioPlayerDelegate {
    var onCompletion: (() -> Void)?
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in self?.onCompletion?() }
    }
    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
        Task { @MainActor [weak self] in self?.onCompletion?() }
    }
}
