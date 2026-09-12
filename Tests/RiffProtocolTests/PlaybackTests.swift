import Foundation
import AVFoundation
import Testing
@testable import RiffProtocol

@MainActor struct PlaybackTests {
    @Test func deviceLoopContinuesPastEndOfAudioAndStops() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 8000, channels: 1))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 400))
        buffer.frameLength = 400
        let samples = try #require(buffer.floatChannelData?[0])
        for index in 0..<400 { samples[index] = 0 }
        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            try file.write(from: buffer)
        }
        let player = try DeviceSoundPlayer(url: url)
        player.volume = 0; player.loops = true
        defer { player.stop() }
        #expect(player.play())
        try await Task.sleep(for: .milliseconds(200))
        #expect(player.isPlaying)
        player.stop()
        #expect(!player.isPlaying)
    }

    @Test func loopSettingSurvivesSavingMergingAndDuplication() throws {
        let original = Pad(id: "music", title: "Music", value: "level-up")
        var loop = original; loop.loop = true
        let restored = try JSONDecoder().decode(Pad.self, from: JSONEncoder().encode(loop))
        #expect(restored.isLooping)
        #expect(restored.duplicated().isLooping)
        let legacy = try JSONDecoder().decode(Pad.self, from: JSONEncoder().encode(original))
        #expect(!legacy.isLooping)
        var remote = original; remote.title = "Renamed music"
        let base = Deck(id: "deck", name: "Music", pads: [original])
        var localDeck = base; localDeck.pads = [loop]
        var remoteDeck = base; remoteDeck.pads = [remote]
        let merged = DeckChanges(base: [base], decks: [localDeck]).merged(with: [remoteDeck])
        #expect(merged.first?.pads.first?.isLooping == true)
        #expect(merged.first?.pads.first?.title == "Renamed music")
        loop.holdAction = PadGestureAction(kind: "sound", value: "nope")
        #expect(loop.resolved(for: .hold)?.isLooping == false)
        let package = try DeckPackage.make(deck: localDeck, snapshot: .starter, grid: GridPreferences())
        #expect(package.compatibilityIssue(in: .starter) == "Update the Windows companion to loop sounds.")
    }

    @Test func loopCanBeStoppedAndQueuedLoopKeepsItsSetting() async throws {
        let sound = try #require(SoundPacks.load().flatMap(\.sounds).first)
        var players: [ControlledSoundPlayer] = []
        let store = RiffStore(cacheURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), pairing: nil, makeLocalSoundPlayer: { _ in
            let player = ControlledSoundPlayer(); players.append(player); return player
        })
        let previousMode = store.soundMode
        defer { store.soundMode = previousMode }
        store.soundMode = .queue
        let first = Pad(id: "first", title: "First", value: sound.clipID)
        let loop = Pad(id: "music", title: "Music", value: sound.clipID, loop: true)
        await store.trigger(first)
        await store.trigger(loop)
        #expect(players.first?.loops == false)
        #expect(store.queuedPadIDs == [loop.id])
        try #require(players.first).finish()
        #expect(players.last?.loops == true)
        #expect(store.playingPadIDs == [loop.id])
        await store.trigger(first)
        await store.trigger(loop)
        #expect(players[1].isPlaying == false)
        #expect(store.playingPadIDs == [first.id])
        await store.trigger(loop)
        try #require(players.last).finish()
        #expect(players.last?.loops == true)
        await store.stopAll()
        #expect(players.allSatisfy { !$0.isPlaying })
        #expect(store.playingPadIDs.isEmpty)
        #expect(store.queuedPadIDs.isEmpty)
    }

    @Test func olderCompanionCannotSilentlyPlayLoopOnce() async {
        let store = RiffStore(cacheURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), pairing: nil)
        store.connected = true
        store.snapshot.capabilities = ["soundboard-playback-v1"]
        await store.trigger(Pad(title: "Music", loop: true))
        #expect(store.error == "Update the Windows companion to loop sounds.")
    }

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
    @Test func queueEditingPreservesCurrentSoundAndPlaysTheNewOrder() async throws {
        let sound = try #require(SoundPacks.load().flatMap(\.sounds).first)
        var players: [ControlledSoundPlayer] = []
        let store = RiffStore(cacheURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), pairing: nil, makeLocalSoundPlayer: { _ in
            let player = ControlledSoundPlayer(); players.append(player); return player
        })
        let originalMode = store.soundMode
        defer { store.soundMode = originalMode }
        store.soundMode = .queue
        for id in ["current", "first", "second", "third"] {
            await store.trigger(Pad(id: id, title: id, value: sound.clipID))
        }
        await store.moveQueuedSound(from: 2, to: 0)
        #expect(store.queuedPadIDs == ["third", "first", "second"])
        await store.moveQueuedSound(from: 1, to: 2)
        #expect(store.queuedPadIDs == ["third", "second", "first"])
        await store.removeQueuedSound(at: 1)
        #expect(store.queuedPadIDs == ["third", "first"])
        #expect(store.playingPadIDs == ["current"])
        #expect(players.count == 1)
        #expect(players[0].isPlaying)
        let beforeCompletion = store.queueContents
        players[0].finish()
        #expect(store.playingPadIDs == ["third"])
        #expect(store.queuedPadIDs == ["first"])
        await store.removeQueuedSound(at: 0, expected: beforeCompletion)
        #expect(store.queuedPadIDs == ["first"])
        #expect(store.error == "The queue changed while you were editing it. Try again.")
        await store.clearQueue()
        #expect(store.queuedPadIDs.isEmpty)
        #expect(store.playingPadIDs == ["third"])
        #expect(players[1].isPlaying)
        players[1].finish()
        #expect(store.playingPadIDs.isEmpty)
        #expect(players.count == 2)
    }

    @Test func queueEditingRequiresCompanionSupport() async {
        let store = RiffStore(cacheURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), pairing: nil)
        #expect(store.supportsQueueEditing)
        store.connected = true
        store.snapshot.capabilities = ["soundboard-queue-v1"]
        store.queuedPadIDs = ["waiting"]
        #expect(!store.supportsQueueEditing)
        await store.clearQueue()
        #expect(store.queuedPadIDs == ["waiting"])
        store.snapshot.capabilities?.append("soundboard-queue-edit-v1")
        #expect(store.supportsQueueEditing)
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
    var loops = false
    var onCompletion: (() -> Void)?

    func play() -> Bool { isPlaying = true; return true }
    func stop() { isPlaying = false }
    func finish() {
        isPlaying = false
        onCompletion?()
    }
}
