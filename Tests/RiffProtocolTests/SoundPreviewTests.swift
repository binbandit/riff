import Foundation
import Testing
@testable import RiffProtocol

@MainActor struct SoundPreviewTests {
    @Test func connectedLibraryPreviewPlaysLocallyWithoutTriggeringPC() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let cache = folder.appendingPathComponent("snapshot.json")
        var state = Snapshot.starter
        state.capabilities = ["clip-audio-v1", "soundboard-playback-v1"]
        state.volume = 0 // Muting PC/game chat must not mute a private iPad preview.
        let clip = Clip(id: "custom-sound", name: "Custom sound", duration: 2)
        state.clips.append(clip)
        try JSONEncoder().encode(state).write(to: cache)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/companion_state_server.py").path, cache.path]
        let pipe = Pipe(); process.standardOutput = pipe
        try process.run()
        defer { process.terminate(); process.waitUntilExit() }
        let pairing = try JSONDecoder().decode(Pairing.self, from: pipe.fileHandleForReading.availableData)
        let client = CompanionClient(pairing: pairing)
        let store = RiffStore(cacheURL: cache, pairing: pairing)
        await store.refresh()
        #expect(store.connected)
        await store.preview(clip)
        #expect(store.error == nil)
        #expect(store.isPreviewPlaying)
        #expect(store.toast == "Playing on iPad: Custom sound")
        struct Counts: Decodable { let audioRequests: Int; let pcPreviews: Int }
        let counts: Counts = try await client.request("/test/preview-counts")
        #expect(counts.audioRequests == 1)
        #expect(counts.pcPreviews == 0)
        store.playingPadIDs = ["pc-pad"]
        store.stopPreview()
        #expect(!store.isPreviewPlaying)
        #expect(store.playingPadIDs == ["pc-pad"])

        await store.testSoundOnPC(clip)
        let afterTest: Counts = try await client.request("/test/preview-counts")
        #expect(afterTest.pcPreviews == 1)
        #expect(!store.isPreviewPlaying)
        #expect(store.toast == "Playing on PC: Custom sound")

        store.snapshot.capabilities = nil
        await store.preview(clip)
        #expect(store.error?.contains("Update Riff on your PC") == true)
        let afterOldCompanion: Counts = try await client.request("/test/preview-counts")
        #expect(afterOldCompanion.pcPreviews == 1)
        #expect(afterOldCompanion.audioRequests == 1)

        store.error = nil
        let packSound = try #require(SoundPacks.load().first?.sounds.first)
        await store.preview(Clip(id: packSound.clipID, name: packSound.name, duration: packSound.duration))
        #expect(store.error == nil)
        #expect(store.isPreviewPlaying)
        store.stopPreview()

        store.snapshot.capabilities = ["clip-audio-v1"]
        let _: Acknowledgement = try await client.request("/test/hold-next-audio")
        let pendingPreview = Task { await store.preview(clip) }
        let started: Acknowledgement = try await client.request("/test/audio-started")
        #expect(started.ok)
        store.stopPreview()
        let _: Acknowledgement = try await client.request("/test/release-audio")
        await pendingPreview.value
        #expect(!store.isPreviewPlaying)
        #expect(store.error == nil)
    }
}
