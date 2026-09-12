import Foundation
import Testing
@testable import RiffProtocol

@MainActor struct PlaybackTests {
    @Test func delayedPollCannotRestoreStoppedButtons() {
        var tracker = SoundPlaybackTracker()
        tracker.accept(SoundPlaybackState(sessionId: "pc", revision: 2, padIds: ["pilot", "meme"]))
        tracker.accept(SoundPlaybackState(sessionId: "pc", revision: 3, padIds: ["meme"]))
        tracker.accept(SoundPlaybackState(sessionId: "pc", revision: 2, padIds: ["pilot", "meme"]))
        #expect(tracker.padIDs == ["meme"])
        tracker.accept(SoundPlaybackState(sessionId: "pc", revision: 4, padIds: []))
        #expect(tracker.padIDs.isEmpty)
    }
    @Test func companionRestartCanResetRevision() {
        var tracker = SoundPlaybackTracker()
        tracker.accept(SoundPlaybackState(sessionId: "old", revision: 40, padIds: ["pilot"]))
        tracker.accept(SoundPlaybackState(sessionId: "new", revision: 0, padIds: []))
        #expect(tracker.padIDs.isEmpty)
        #expect(tracker.state?.sessionId == "new")
    }
    @Test func cachedAndOlderSnapshotsDoNotRequirePlaybackCapability() throws {
        let data = try JSONEncoder().encode(Snapshot.starter)
        let old = try JSONDecoder().decode(Snapshot.self, from: data)
        #expect(old.capabilities == nil)
        var current = old
        current.capabilities = ["soundboard-playback-v1"]
        let restored = try JSONDecoder().decode(Snapshot.self, from: JSONEncoder().encode(current))
        #expect(restored.capabilities == ["soundboard-playback-v1"])
    }
    @Test func queueOrderSurvivesDelayedStatusAndOlderCompanions() throws {
        var tracker = SoundPlaybackTracker()
        tracker.accept(SoundPlaybackState(sessionId: "pc", revision: 4, padIds: ["first"], queuedPadIds: ["third", "second"]))
        tracker.accept(SoundPlaybackState(sessionId: "pc", revision: 3, padIds: ["first"], queuedPadIds: ["second"]))
        #expect(tracker.queuedPadIDs == ["third", "second"])
        let old = try JSONDecoder().decode(SoundPlaybackState.self, from: Data(#"{"sessionId":"old","revision":0,"padIds":[]}"#.utf8))
        tracker.accept(old)
        #expect(tracker.queuedPadIDs.isEmpty)
    }
    @Test func olderCompanionUsesSingleUntilQueueIsSupported() {
        let store = RiffStore(cacheURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), pairing: nil)
        let originalMode = store.soundMode
        defer { store.soundMode = originalMode }
        store.soundMode = .queue
        store.connected = true
        store.snapshot.capabilities = ["soundboard-playback-v1"]
        #expect(store.effectiveSoundMode == .single)
        #expect(!store.availablePlaybackModes.contains(.queue))
        store.snapshot.capabilities?.append("soundboard-queue-v1")
        #expect(store.effectiveSoundMode == .queue)
        #expect(store.availablePlaybackModes.contains(.queue))
    }
    @Test func offlineQueueSupportsRemovingSkippingAndStopAll() async throws {
        let sound = try #require(SoundPacks.load().flatMap(\.sounds).first { $0.id == "sad-violin" })
        let store = RiffStore(cacheURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), pairing: nil)
        let originalMode = store.soundMode
        defer { store.soundMode = originalMode }
        store.snapshot.volume = 0; store.soundMode = .queue
        let first = Pad(id: "first", title: "First", value: sound.clipID)
        let second = Pad(id: "second", title: "Second", value: sound.clipID)
        let third = Pad(id: "third", title: "Third", value: sound.clipID)
        await store.trigger(first); await store.trigger(second); await store.trigger(third)
        #expect(store.error == nil)
        #expect(store.playingPadIDs == ["first"])
        #expect(store.queuedPadIDs == ["second", "third"])
        #expect(store.queuePosition(for: "third") == 2)
        await store.trigger(second)
        #expect(store.playingPadIDs == ["first"])
        #expect(store.queuedPadIDs == ["third"])
        await store.trigger(first)
        #expect(store.playingPadIDs == ["third"])
        #expect(store.queuedPadIDs.isEmpty)
        await store.trigger(second)
        await store.stopAll()
        await store.refreshPlayback()
        #expect(store.playingPadIDs.isEmpty)
        #expect(store.queuedPadIDs.isEmpty)
    }
    @Test func switchingAwayFromQueueClearsWaitingSoundsOnNextTap() async throws {
        let sound = try #require(SoundPacks.load().flatMap(\.sounds).first { $0.id == "sad-violin" })
        let store = RiffStore(cacheURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), pairing: nil)
        let originalMode = store.soundMode
        defer { store.soundMode = originalMode }
        store.snapshot.volume = 0; store.soundMode = .queue
        await store.trigger(Pad(id: "first", title: "First", value: sound.clipID))
        await store.trigger(Pad(id: "waiting", title: "Waiting", value: sound.clipID))
        store.soundMode = .overlap
        await store.trigger(Pad(id: "new", title: "New", value: sound.clipID))
        #expect(store.queuedPadIDs.isEmpty)
        #expect(store.playingPadIDs == ["first", "new"])
        await store.stopAll()
    }
    @Test func offlineQueueAdvancesOnCompletionWithoutPolling() async throws {
        let sound = try #require(SoundPacks.load().flatMap(\.sounds).first)
        var players: [ControlledSoundPlayer] = []
        let store = RiffStore(cacheURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), pairing: nil, makeLocalSoundPlayer: { _ in
            let player = ControlledSoundPlayer()
            players.append(player)
            return player
        })
        let originalMode = store.soundMode
        defer { store.soundMode = originalMode }
        store.snapshot.volume = 0; store.soundMode = .queue
        await store.trigger(Pad(id: "first", title: "First", value: sound.clipID))
        await store.trigger(Pad(id: "second", title: "Second", value: sound.clipID))
        #expect(store.playingPadIDs == ["first"])
        #expect(store.queuedPadIDs == ["second"])
        #expect(players.count == 1)

        // Deliver the audio completion event without relying on a CI audio device or wall-clock timing.
        try #require(players.first).finish()
        #expect(store.error == nil)
        #expect(store.playingPadIDs == ["second"])
        #expect(store.queuedPadIDs.isEmpty)
        #expect(players.count == 2)
        #expect(players.last?.isPlaying == true)

        try #require(players.last).finish()
        #expect(store.playingPadIDs.isEmpty)
        #expect(store.queuedPadIDs.isEmpty)
        await store.stopAll()
    }
}

@MainActor private final class ControlledSoundPlayer: LocalSoundPlayer {
    private(set) var isPlaying = false
    var volume: Float = 1
    var onCompletion: (() -> Void)?

    func play() -> Bool { isPlaying = true; return true }
    func stop() { isPlaying = false }
    func finish() {
        isPlaying = false
        onCompletion?()
    }
}
