import Foundation

struct ReleaseVersion: Comparable {
    let numbers: [Int]
    let prerelease: [String]
    init?(_ text: String) {
        guard !text.isEmpty, text.utf8.count <= 128 else { return nil }
        let raw = text.hasPrefix("v") ? String(text.dropFirst()) : text
        let buildParts = raw.split(separator: "+", omittingEmptySubsequences: false)
        guard buildParts.count <= 2 else { return nil }
        func identifiers(_ value: Substring) -> [String]? {
            let parts = value.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
            guard parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") } }) else { return nil }
            return parts
        }
        if buildParts.count == 2 && identifiers(buildParts[1]) == nil { return nil }
        let parts = buildParts[0].split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let core = parts[0].split(separator: ".", omittingEmptySubsequences: false)
        guard core.count == 3, core.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } && ($0.count == 1 || !$0.hasPrefix("0")) }) else { return nil }
        let numbers = core.compactMap { Int($0) }
        guard numbers.count == 3 else { return nil }
        self.numbers = numbers
        if parts.count == 2 {
            guard let labels = identifiers(parts[1]), labels.allSatisfy({ !$0.allSatisfy(\.isNumber) || $0.count == 1 || !$0.hasPrefix("0") }) else { return nil }
            prerelease = labels
        } else { prerelease = [] }
    }
    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.numbers != rhs.numbers { return lhs.numbers.lexicographicallyPrecedes(rhs.numbers) }
        if lhs.prerelease.isEmpty { return false }
        if rhs.prerelease.isEmpty { return true }
        for (left, right) in zip(lhs.prerelease, rhs.prerelease) where left != right {
            let ln = left.allSatisfy(\.isNumber), rn = right.allSatisfy(\.isNumber)
            if ln != rn { return ln }
            if ln && left.count != right.count { return left.count < right.count }
            return left < right
        }
        return lhs.prerelease.count < rhs.prerelease.count
    }
}

struct GitHubRelease: Codable {
    struct Asset: Codable { let name: String; let state: String; let size: Int64 }
    let tag_name: String
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]
    var version: ReleaseVersion? {
        ReleaseVersion(tag_name.hasPrefix("companion-") ? String(tag_name.dropFirst("companion-".count)) : tag_name)
    }
    var isStable: Bool { !draft && !prerelease && version?.prerelease.isEmpty == true }
    var isWindowsRelease: Bool {
        guard !draft, !prerelease, let version, version.prerelease.isEmpty else { return false }
        let number = version.numbers.map(String.init).joined(separator: ".")
        let names = ["Riff-\(number)-win-x64.zip", "Riff-\(number)-win-arm64.zip", "Riff-win-x64.zip", "Riff-win-arm64.zip"]
        return assets.contains { names.contains($0.name) && $0.state == "uploaded" && $0.size > 0 }
    }
    var page: URL {
        // Use a fixed repository and a validated version, never a URL supplied by the PC or release notes.
        guard isWindowsRelease else { return Self.releasesPage }
        return Self.releasesPage.appendingPathComponent("tag").appendingPathComponent(tag_name)
    }
    static let releasesPage = URL(string: "https://github.com/binbandit/riff/releases")!
    func isNewer(than installed: String?) -> Bool {
        guard isWindowsRelease, let latest = version, let installed, let current = ReleaseVersion(installed) else { return false }
        return latest > current
    }
}

enum GitHubReleaseClient {
    static func request(page: Int = 1) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/binbandit/riff/releases?per_page=100&page=\(page)")!)
        request.timeoutInterval = 10
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Riff-iPad", forHTTPHeaderField: "User-Agent")
        return request
    }
    static func decode(_ data: Data, status: Int) throws -> [GitHubRelease] {
        if status == 404 { return [] }
        if status == 403 || status == 429 { throw RiffError.message("GitHub is limiting update checks. Try again later.") }
        guard status == 200 else { throw RiffError.message("GitHub couldn’t check for updates. Try again later.") }
        guard data.count <= 2 * 1024 * 1024, let releases = try? JSONDecoder().decode([GitHubRelease].self, from: data) else {
            throw RiffError.message("GitHub returned an unreadable release list. Try again later.")
        }
        return releases
    }
    static func latest(in releases: [GitHubRelease]) throws -> GitHubRelease? {
        let candidates = releases.filter { $0.isStable && ($0.tag_name.hasPrefix("companion-v") || $0.isWindowsRelease) }
        guard let latest = candidates.max(by: { $0.version! < $1.version! }) else { return nil }
        guard latest.isWindowsRelease else { throw RiffError.message("The newest companion release doesn’t have a Windows download ready yet.") }
        return latest
    }
    static func fetch() async throws -> GitHubRelease? {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForResource = 15
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        return try await fetchPages { page in
            let (data, response) = try await session.data(for: request(page: page))
            guard let http = response as? HTTPURLResponse else { throw RiffError.message("GitHub did not respond.") }
            return try decode(data, status: http.statusCode)
        }
    }
    static func fetchPages(_ read: (Int) async throws -> [GitHubRelease]) async throws -> GitHubRelease? {
        var releases: [GitHubRelease] = []
        for page in 1...10 {
            try Task.checkCancellation()
            let batch = try await read(page)
            releases += batch
            if batch.count < 100 { return try latest(in: releases) }
        }
        // Never declare an older release current after only checking part of a large history.
        throw RiffError.message("The release history is too large to check completely. Open GitHub to see the latest downloads.")
    }
}
