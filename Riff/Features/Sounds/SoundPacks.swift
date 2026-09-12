import Foundation
import CryptoKit

struct SoundPack: Decodable, Identifiable {
    let id: String
    let name: String
    let description: String
    let icon: String
    let color: String
    let sounds: [PackSound]
    func installed(in clips: [Clip]) -> [Clip] {
        let byID = Dictionary(clips.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return sounds.compactMap { byID[$0.clipID] }
    }
    func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty || ([name, description] + sounds.map(\.name)).contains { $0.localizedStandardContains(query) }
    }
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
