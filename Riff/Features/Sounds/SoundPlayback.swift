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
        case .queue: "Sounds play in the order you tap them. Open the queue to reorder or clear waiting sounds. Tap a waiting sound to remove it, or a playing sound to skip it. Stop all also clears the queue."
        }
    }
}

struct SoundPlaybackState: Codable, Equatable {
    let sessionId: String
    let revision: Int64
    let padIds: [String]
    var queuedPadIds: [String]? = nil
}

struct SoundQueueContents: Equatable {
    let padIDs: [String]
    let sessionID: String?
    let revision: Int64?
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

protocol LocalSoundPlayer: AnyObject {
    var isPlaying: Bool { get }
    var volume: Float { get set }
    var loops: Bool { get set }
    var onCompletion: (() -> Void)? { get set }
    func play() -> Bool
    func stop()
}

final class DeviceSoundPlayer: NSObject, LocalSoundPlayer, AVAudioPlayerDelegate {
    private let player: AVAudioPlayer
    var onCompletion: (() -> Void)?

    init(url: URL) throws {
        player = try AVAudioPlayer(contentsOf: url)
        super.init()
        player.delegate = self
    }

    var isPlaying: Bool { player.isPlaying }
    var volume: Float {
        get { player.volume }
        set { player.volume = newValue }
    }
    var loops: Bool {
        get { player.numberOfLoops == -1 }
        set { player.numberOfLoops = newValue ? -1 : 0 }
    }
    func play() -> Bool { player.play() }
    func stop() { player.stop() }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in self?.onCompletion?() }
    }
    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
        Task { @MainActor [weak self] in self?.onCompletion?() }
    }
}
