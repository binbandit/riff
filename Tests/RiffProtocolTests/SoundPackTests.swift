import Foundation
import AVFoundation
import Testing
@testable import RiffProtocol

@MainActor struct SoundPackTests {
    @Test func catalogHasUniqueSoundsAndIncludesEverySoundInStarterLibrary() throws {
        let packs = try SoundPacks.load()
        let sounds = packs.flatMap(\.sounds)
        #expect(packs.count >= 14 && sounds.count >= 138)
        #expect(Set(sounds.map(\.id)).count == sounds.count)
        #expect(Set(sounds.map(\.sha256)).count == sounds.count)
        #expect(Set(packs.map(\.id)).count == packs.count)
        #expect(Set(sounds.map(\.clipID)).isSubset(of: Set(Snapshot.starter.clips.map(\.id))))
        for sound in sounds {
            #expect(sound.fileName == "\(sound.id)-\(sound.sha256).mp3" && sound.sourceURL.scheme == "https")
            #expect(sound.byteCount > 0 && sound.byteCount < 20 * 1024 * 1024)
            #expect(sound.duration > 0 && sound.duration <= 60)
            #expect(sound.sha256.count == 64)
            #expect(!sound.provider.isEmpty && !sound.rights.isEmpty)
        }
    }
    @Test func requestedClipsKeepTheirExactSourceAndAudio() throws {
        let sounds = try SoundPacks.load().flatMap(\.sounds)
        let violin = try #require(sounds.first { $0.id == "sad-violin" })
        #expect(violin.sourceURL.absoluteString == "https://www.myinstants.com/en/instant/sad-violin-the-meme-one/")
        #expect(violin.sha256 == "6aa0f62297c2154fbf715e1f43b435c0a468b4083bbdc91200531ba96fce5324")
        let smoke = try #require(sounds.first { $0.id == "smoke-detector" })
        #expect(smoke.sourceURL.absoluteString == "https://www.myinstants.com/en/instant/smoke-detector-beep-97430/")
        #expect(sounds.contains { $0.sourceURL.absoluteString == "https://www.myinstants.com/en/instant/they-ask-you-how-you-are-meme-/" })
        #expect(sounds.contains { $0.sourceURL.absoluteString == "https://www.myinstants.com/en/instant/social-credit-music-63796/" })
        #expect(sounds.contains { $0.sourceURL.absoluteString == "https://www.myinstants.com/en/instant/welcome-aboard-delta-airlines-82730/" })
        #expect(sounds.contains { $0.sourceURL.absoluteString == "https://www.101soundboards.com/sounds/1506614-and-we-say-bye-bye" && $0.sha256 == "15a70c42b337bc7f7e8c7f4bf7e520905d37fce420349cce271e786c768987d8" })
        #expect(sounds.contains { $0.sourceURL.absoluteString == "https://www.101soundboards.com/sounds/61212-car-horns-heavy-traffic" && $0.sha256 == "d59d7291a6a29fbd10ec3ad4d2a17867714c4388c7b50f302d48d466e36f1075" })
        let pimpDown = try #require(sounds.first { $0.id == "pimp-down" })
        #expect(pimpDown.sourceURL.absoluteString == "https://tuna.voicemod.net/sound/24402367-2e4c-449a-81e2-7746a0613e2c")
        #expect(pimpDown.sha256 == "55b967d096de6c1b54bb33fb5e0f0705a4568ce1fd4bd187162ee64f4bfb8fcd")
    }
    @Test func everySoundIsBundledAndPlayableOffline() throws {
        for sound in try SoundPacks.load().flatMap(\.sounds) {
            let url = try SoundPacks.audioURL(for: sound)
            #expect(url.isFileURL)
            #expect(SoundPacks.audioURL(forClipID: sound.clipID) == url)
            let data = try SoundPacks.audioData(for: sound)
            #expect(data.count == sound.byteCount)
            let player = try AVAudioPlayer(contentsOf: url)
            #expect(player.duration > 0 && player.duration <= 60)
            if sound.id.hasPrefix("comms-") {
                #expect(player.duration < 5)
            }
        }
        #expect(SoundPacks.audioURL(forClipID: "unknown") == nil)
    }
    @Test func packButtonsAndLibraryPreviewsPlayWithoutAPC() async throws {
        let sound = try #require(SoundPacks.load().flatMap(\.sounds).first { $0.id == "sad-violin" })
        let store = RiffStore(cacheURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), pairing: nil)
        store.snapshot.volume = 0
        let pad = Pad(id: "offline-pack-pad", title: "My reaction", value: sound.clipID)
        await store.trigger(pad)
        #expect(!store.connected)
        #expect(store.error == nil)
        #expect(store.playingPadIDs == [pad.id])
        await store.stopAll()
        #expect(store.playingPadIDs.isEmpty)
        await store.preview(Clip(id: sound.clipID, name: "My reaction", duration: sound.duration))
        #expect(store.error == nil)
        #expect(store.toast == "Playing on iPad: My reaction")
        await store.stopAll()
    }
    @Test func deletedSoundsStayDeletedAfterRelaunchAndLegacyCachesGainTheCatalog() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let cache = folder.appendingPathComponent("snapshot.json")
        var legacy = Snapshot.starter
        legacy.clips.removeAll { $0.id.hasPrefix("pack-") }
        try JSONEncoder().encode(legacy).write(to: cache)
        let store = RiffStore(cacheURL: cache, pairing: nil)
        let clip = try #require(store.snapshot.clips.first { $0.id == "pack-sad-violin" })
        #expect(store.snapshot.clips.count == Snapshot.starter.clips.count)
        await store.deleteClip(clip)
        #expect(store.error == nil)
        let restored = RiffStore(cacheURL: cache, pairing: nil)
        #expect(!restored.snapshot.clips.contains { $0.id == clip.id })
        #expect(restored.snapshot.clips.count == Snapshot.starter.clips.count - 1)
        let used = try #require(restored.snapshot.clips.first { $0.id == "level-up" })
        await restored.deleteClip(used)
        #expect(restored.error != nil)
        #expect(restored.snapshot.clips.contains { $0.id == used.id })
    }

    @Test func offlineDeletionSyncsAfterRestartWithoutRestoringTheSound() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let remote = folder.appendingPathComponent("remote.json"), cache = folder.appendingPathComponent("cache.json")
        try JSONEncoder().encode(Snapshot.starter).write(to: remote)
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/companion_state_server.py").path, remote.path]
        let pipe = Pipe(); process.standardOutput = pipe
        try process.run()
        defer { process.terminate(); process.waitUntilExit() }
        let pairing = try JSONDecoder().decode(Pairing.self, from: pipe.fileHandleForReading.availableData)
        let store = RiffStore(cacheURL: cache, pairing: nil)
        let clip = try #require(store.snapshot.clips.first { $0.id == "pack-sad-violin" })
        await store.deleteClip(clip)
        let restored = RiffStore(cacheURL: cache, pairing: pairing)
        await restored.refresh()
        let client = CompanionClient(pairing: pairing)
        let state: Snapshot = try await client.request("/api/state")
        #expect(!state.clips.contains { $0.id == clip.id })
        #expect(!restored.snapshot.clips.contains { $0.id == clip.id })
        #expect(!RiffStore(cacheURL: cache, pairing: nil).snapshot.clips.contains { $0.id == clip.id })
        #expect(restored.error == nil)
    }

    @Test func correctedMusicUpdatesCachedDurationAndPreservesItsIdentity() throws {
        let sound = try #require(SoundPacks.load().flatMap(\.sounds).first { $0.id == "chipi-chapa" })
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let cache = folder.appendingPathComponent("snapshot.json")
        var old = Snapshot.starter
        let index = try #require(old.clips.firstIndex { $0.id == sound.clipID })
        old.clips[index].name = "My music"; old.clips[index].duration = 11.991
        try JSONEncoder().encode(old).write(to: cache)
        let store = RiffStore(cacheURL: cache, pairing: nil)
        let corrected = try #require(store.snapshot.clips.first { $0.id == sound.clipID })
        #expect(corrected.name == "My music")
        #expect(corrected.duration == sound.duration)
        #expect(store.snapshot.decks == old.decks)
        let player = try AVAudioPlayer(contentsOf: SoundPacks.audioURL(for: sound))
        #expect(player.duration > 9.7 && player.duration < 9.9)
        #expect(abs(player.duration - sound.duration) < 0.05)
    }

    @Test func corruptTruncatedAndOversizedAudioIsRejected() throws {
        let sound = try #require(SoundPacks.load().first?.sounds.first)
        let data = try SoundPacks.audioData(for: sound)
        var corrupt = data
        corrupt[0] ^= 0xff
        for invalid in [corrupt, Data(data.dropLast()), data + Data([0])] {
            #expect(throws: (any Error).self) { try sound.validate(invalid) }
        }
    }
}
