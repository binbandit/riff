import Foundation
import CryptoKit

struct SoundPack: Decodable, Identifiable {
    let id: String
    let name: String
    let description: String
    let icon: String
    let color: String
    let sounds: [PackSound]
    var byteCount: Int { sounds.reduce(0) { $0 + $1.byteCount } }
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
    let url: URL
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
            throw RiffError.message("The download for \(name) changed or is incomplete. Try again or check for a Riff update.")
        }
    }
}

enum SoundPacks {
    static func load() throws -> [SoundPack] {
#if SWIFT_PACKAGE
        let bundle = Bundle.module
#else
        let bundle = Bundle.main
#endif
        guard let url = bundle.url(forResource: "sound-packs", withExtension: "json") else {
            throw RiffError.message("The sound pack catalog is missing. Reinstall Riff to restore it.")
        }
        return try JSONDecoder().decode([SoundPack].self, from: Data(contentsOf: url))
    }

    static func download(_ sound: PackSound, session: URLSession = .shared) async throws -> Data {
        var request = URLRequest(url: sound.url)
        request.setValue("Riff/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30
        // Bound the response while receiving it, including chunked responses without a content length.
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              response.url?.scheme == "https" else {
            throw RiffError.message("\(sound.name) could not be downloaded. Try again later.")
        }
        guard response.expectedContentLength <= Int64(sound.byteCount) else {
            throw RiffError.message("The download for \(sound.name) has changed. Check for a Riff update.")
        }
        var data = Data(); data.reserveCapacity(sound.byteCount)
        for try await byte in bytes {
            guard data.count < sound.byteCount else { throw RiffError.message("The sound download is larger than expected.") }
            data.append(byte)
        }
        try Task.checkCancellation()
        try sound.validate(data)
        return data
    }
}
