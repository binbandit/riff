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
}
