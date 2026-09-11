import Foundation
import Observation

enum ReleaseChangelogClient {
    static let maximumBytes = 1_048_576
    static func request(for release: GitHubRelease) throws -> URLRequest {
        guard release.isWindowsRelease, let asset = release.changelogAsset else {
            throw RiffError.message("This release doesn’t include a CHANGELOG.md file. You can still view its release page.")
        }
        guard asset.size <= maximumBytes else { throw RiffError.message("This changelog is too large to display. Open the release page to read it.") }
        let url: URL
        if let id = asset.id, id > 0 {
            url = URL(string: "https://api.github.com/repos/binbandit/riff/releases/assets/\(id)")!
        } else {
            url = GitHubRelease.releasesPage.appendingPathComponent("download").appendingPathComponent(release.tag_name).appendingPathComponent(asset.name)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Riff-iPad", forHTTPHeaderField: "User-Agent")
        return request
    }
    static func decode(_ data: Data) throws -> String {
        guard !data.isEmpty, data.count <= maximumBytes,
              let markdown = String(data: data, encoding: .utf8), !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RiffError.message("The changelog couldn’t be read. Open the release page or try again.")
        }
        return markdown
    }
    static func fetch(_ release: GitHubRelease) async throws -> String {
        let request = try request(for: release)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForResource = 20
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw RiffError.message("The changelog isn’t available right now. Try again or view the release page.")
        }
        guard response.expectedContentLength <= maximumBytes else { throw RiffError.message("This changelog is too large to display. Open the release page to read it.") }
        var data = Data()
        for try await byte in bytes {
            guard data.count < maximumBytes else { throw RiffError.message("This changelog is too large to display. Open the release page to read it.") }
            data.append(byte)
        }
        return try decode(data)
    }
}

@MainActor @Observable final class ReleaseChangelogStore {
    private struct Cache: Codable { let key: String; let markdown: String; let savedAt: Date }
    private(set) var markdown: String?
    private(set) var loading = false
    private(set) var failure: String?
    private var loadedKey: String?
    private var requestID = UUID()
    private var loadingKey: String?
    private let cacheURL: URL
    private let fetch: (GitHubRelease) async throws -> String
    init(cacheURL: URL = URL.cachesDirectory.appendingPathComponent("companion-changelog.json"), fetch: @escaping (GitHubRelease) async throws -> String = ReleaseChangelogClient.fetch) {
        self.cacheURL = cacheURL; self.fetch = fetch
    }
    func load(_ release: GitHubRelease, force: Bool = false, now: Date = Date()) async {
        let key = release.changelogKey
        if loading && loadingKey == key { return }
        let token = UUID(); requestID = token
        if loadedKey != key { markdown = nil; failure = nil; loadedKey = key }
        loading = false; loadingKey = nil
        guard let key else {
            markdown = nil; failure = "This release doesn’t include a CHANGELOG.md file. You can still view its release page."; return
        }
        if !force, let size = try? cacheURL.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= ReleaseChangelogClient.maximumBytes * 2,
           let data = try? Data(contentsOf: cacheURL), let cache = try? JSONDecoder().decode(Cache.self, from: data), cache.key == key,
           (try? ReleaseChangelogClient.decode(Data(cache.markdown.utf8))) != nil {
            markdown = cache.markdown
            if (0..<6 * 3600).contains(now.timeIntervalSince(cache.savedAt)) { failure = nil; return }
        }
        loading = true; loadingKey = key; failure = nil
        defer { if requestID == token { loading = false; loadingKey = nil } }
        do {
            let text = try await fetch(release)
            guard requestID == token, !Task.isCancelled else { return }
            markdown = try ReleaseChangelogClient.decode(Data(text.utf8))
            let cache = Cache(key: key, markdown: text, savedAt: now)
            // Disk caching is optional. A failed write must not hide a downloaded changelog.
            if let data = try? JSONEncoder().encode(cache) {
                try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? data.write(to: cacheURL, options: .atomic)
            }
        } catch {
            guard requestID == token, !Task.isCancelled else { return }
            failure = error is RiffError ? error.localizedDescription : "Couldn’t download the changelog. Check your internet connection and try again."
        }
    }
}
