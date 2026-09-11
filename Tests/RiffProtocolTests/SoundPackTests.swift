import Foundation
import CryptoKit
import Testing
@testable import RiffProtocol

@MainActor struct SoundPackTests {
    @Test func catalogHasUniqueSoundsAndKeepsDownloadsOutOfStarterLibrary() throws {
        let packs = try SoundPacks.load()
        let sounds = packs.flatMap(\.sounds)
        #expect(packs.count == 5 && sounds.count >= 35)
        #expect(Set(sounds.map(\.id)).count == sounds.count)
        #expect(Set(packs.map(\.id)).count == packs.count)
        #expect(Set(sounds.map(\.clipID)).isDisjoint(with: Snapshot.starter.clips.map(\.id)))
        for sound in sounds {
            #expect(sound.url.scheme == "https" && sound.sourceURL.scheme == "https")
            #expect(sound.byteCount > 0 && sound.byteCount < 20 * 1024 * 1024)
            #expect(sound.duration > 0 && sound.duration <= 60)
            #expect(sound.sha256.count == 64)
            #expect(!sound.provider.isEmpty && !sound.rights.isEmpty)
        }
    }
    @Test func requestedClipsKeepTheirExactSourceAndDownload() throws {
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
    @Test func githubDownloadsMatchRepositoryAudio() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for sound in try SoundPacks.load().flatMap(\.sounds) {
            let path = "sound-packs/audio/\(sound.id)-\(sound.sha256).mp3"
            #expect(sound.url.absoluteString == "https://raw.githubusercontent.com/binbandit/riff/main/" + path)
            try sound.validate(Data(contentsOf: root.appendingPathComponent(path)))
        }
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
    @Test func downloaderRejectsErrorsOversizeAndChangedContent() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [PackDownloadProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        for path in ["ok", "corrupt", "oversized", "missing", "truncated"] {
            let data = Data("sound".utf8)
            let sound = PackSound(id: "test", name: "Test", url: URL(string: "https://pack.test/" + path)!, sourceURL: URL(string: "https://pack.test")!, provider: "Test", uploader: "Test", rights: "Test", byteCount: data.count, sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), duration: 1)
            do {
                let downloaded = try await SoundPacks.download(sound, session: session)
                #expect(path == "ok")
                #expect(downloaded == data)
            } catch { #expect(path != "ok") }
        }
    }
    @Test func liveCatalogDownloadsMatchReviewedBytes() async throws {
        guard ProcessInfo.processInfo.environment["RIFF_TEST_PACK_DOWNLOADS"] == "1" else { return }
        for sound in try SoundPacks.load().flatMap(\.sounds) {
            let data = try await SoundPacks.download(sound)
            #expect(data.count == sound.byteCount)
        }
    }
}

private final class PackDownloadProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let path = request.url!.lastPathComponent
        let response = HTTPURLResponse(url: request.url!, statusCode: path == "missing" ? 404 : 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let content = switch path { case "corrupt": "noise"; case "oversized": "too much data"; case "truncated": "s"; default: "sound" }
        client?.urlProtocol(self, didLoad: Data(content.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
