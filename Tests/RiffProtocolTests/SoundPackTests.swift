import Foundation
import AVFoundation
import Testing
@testable import RiffProtocol

@MainActor struct SoundPackTests {
    @Test func catalogHasUniqueSoundsAndKeepsPacksOutOfStarterLibrary() throws {
        let packs = try SoundPacks.load()
        let sounds = packs.flatMap(\.sounds)
        #expect(packs.count == 5 && sounds.count >= 35)
        #expect(Set(sounds.map(\.id)).count == sounds.count)
        #expect(Set(packs.map(\.id)).count == packs.count)
        #expect(Set(sounds.map(\.clipID)).isDisjoint(with: Snapshot.starter.clips.map(\.id)))
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
        }
        #expect(SoundPacks.audioURL(forClipID: "unknown") == nil)
    }
    @Test func partialInstallUsesStableIDsAndPreservesRenames() throws {
        let pack = try #require(SoundPacks.load().first)
        let renamed = Clip(id: pack.sounds[1].clipID, name: "My reaction", duration: 2)
        let other = Clip(id: "unrelated", name: pack.sounds[0].name, duration: 1)
        #expect(pack.installed(in: [other, renamed]).map(\.id) == [renamed.id])
        #expect(pack.installed(in: [renamed]).first?.name == "My reaction")
        #expect(pack.installed(in: []).isEmpty)
        #expect(pack.matches("  BRUH  "))
        #expect(!pack.matches("not-a-real-sound"))
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
