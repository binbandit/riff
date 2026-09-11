import Foundation
import Observation

@MainActor @Observable final class CompanionUpdates {
    private struct Cache: Codable { let release: GitHubRelease?; let checkedAt: Date }
    private(set) var release: GitHubRelease?
    private(set) var checkedAt: Date?
    private(set) var checking = false
    private(set) var failure: String?
    private var attemptedAt: Date?
    private let defaults: UserDefaults
    private let fetch: () async throws -> GitHubRelease?
    init(defaults: UserDefaults = .standard, fetch: @escaping () async throws -> GitHubRelease? = GitHubReleaseClient.fetch) {
        self.defaults = defaults; self.fetch = fetch
        if let data = defaults.data(forKey: "companionReleaseCache"), let cache = try? JSONDecoder().decode(Cache.self, from: data), cache.release == nil || cache.release?.isWindowsRelease == true {
            release = cache.release; checkedAt = cache.checkedAt
        }
        attemptedAt = defaults.object(forKey: "companionReleaseAttempt") as? Date
    }
    func check(force: Bool = false, now: Date = Date()) async {
        guard !checking else { return }
        if !force {
            if let checkedAt, (0..<6 * 3600).contains(now.timeIntervalSince(checkedAt)) { return }
            if let attemptedAt, (0..<15 * 60).contains(now.timeIntervalSince(attemptedAt)) { return }
        }
        checking = true; failure = nil
        attemptedAt = now; defaults.set(now, forKey: "companionReleaseAttempt")
        defer {
            checking = false
            if Task.isCancelled { attemptedAt = nil; defaults.removeObject(forKey: "companionReleaseAttempt") }
        }
        do {
            let latest = try await fetch()
            guard !Task.isCancelled else { return }
            release = latest; checkedAt = now
            if let data = try? JSONEncoder().encode(Cache(release: latest, checkedAt: now)) { defaults.set(data, forKey: "companionReleaseCache") }
        } catch is CancellationError { }
        catch {
            guard !Task.isCancelled else { return }
            failure = error is RiffError ? error.localizedDescription : "Couldn’t reach GitHub. Your soundboard still works on your local network."
        }
    }
}
