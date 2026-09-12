import Foundation
import CryptoKit

struct SoundPack: Decodable, Identifiable {
    let id: String
    let name: String
    let description: String
    let icon: String
    let color: String
    let sounds: [PackSound]

}

struct PackSound: Decodable, Identifiable {
    let id: String
    let name: String
    let fileName: String
    let sourceURL: URL
    let provider: String
    let uploader: String
    let rights: String
    let byteCount: Int
    let sha256: String
    let duration: Double
    var clipID: String { "pack-" + id }

    func validate(_ data: Data) throws {
        guard data.count == byteCount,
              SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == sha256 else {
            throw RiffError.message("The bundled audio for \(name) is damaged. Reinstall Riff to restore it.")
        }
    }
}

enum SoundPacks {
    private static var bundle: Bundle {
#if SWIFT_PACKAGE
        Bundle.module
#else
        Bundle.main
#endif
    }

    static var clips: [Clip] { (try? load())?.flatMap { $0.sounds.map { Clip(id: $0.clipID, name: $0.name, duration: $0.duration) } } ?? [] }

    static func load() throws -> [SoundPack] {
        guard let url = bundle.url(forResource: "sound-packs", withExtension: "json") else {
            throw RiffError.message("The sound pack catalog is missing. Reinstall Riff to restore it.")
        }
        return try JSONDecoder().decode([SoundPack].self, from: Data(contentsOf: url))
    }

    static func audioURL(for sound: PackSound) throws -> URL {
        guard let url = bundle.url(forResource: sound.fileName, withExtension: nil) else {
            throw RiffError.message("The bundled audio for \(sound.name) is missing. Reinstall Riff to restore it.")
        }
        return url
    }

    static func audioData(for sound: PackSound) throws -> Data {
        let data = try Data(contentsOf: audioURL(for: sound))
        try sound.validate(data)
        return data
    }

    static func audioURL(forClipID clipID: String) -> URL? {
        guard let sound = try? load().flatMap(\.sounds).first(where: { $0.clipID == clipID }) else { return nil }
        return try? audioURL(for: sound)
    }
}
