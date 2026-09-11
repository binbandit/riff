import Foundation
import Testing
@testable import RiffProtocol

@MainActor struct CompanionUpdateTests {
    private func release(_ tag: String = "v1.2.0") -> GitHubRelease {
        GitHubRelease(tag_name: tag, draft: false, prerelease: false, assets: [.init(name: "Riff-win-x64.zip", state: "uploaded", size: 100)])
    }
    @Test func comparesVersionsNumericallyAndUsesSemanticPrereleaseOrder() throws {
        let ascending = ["1.2.0-alpha", "1.2.0-alpha.2", "1.2.0-alpha.10", "1.2.0-beta", "1.2.0-rc.1", "1.2.0", "1.10.0", "2.0.0"]
        for pair in zip(ascending, ascending.dropFirst()) {
            #expect(try #require(ReleaseVersion(pair.0)) < #require(ReleaseVersion(pair.1)))
        }
        #expect(ReleaseVersion("v1.2.0+abc") == ReleaseVersion("1.2.0+def"))
        #expect(release("v1.10.0").isNewer(than: "1.9.0"))
        #expect(!release().isNewer(than: "1.2.0"))
        #expect(!release().isNewer(than: "2.0.0"))
        #expect(!release().isNewer(than: nil))
        #expect(!release().isNewer(than: "unknown"))
        #expect(release().isNewer(than: "1.2.0-beta.1"))
    }
    @Test func rejectsMalformedAndUnsafeReleaseVersions() {
        for value in ["", "v", "1.2", "01.2.3", "1.2.3.4", "1.2.3-", "1.2.3+", "1.2.3-01", "1.2.3+foo+bar", "1.2.3/evil", "https://evil.test", "1.2.9999999999999999999999999999999", " 1.2.3", "1.2.3\n"] {
            #expect(ReleaseVersion(value) == nil, "Accepted \(value)")
        }
    }
    @Test func onlyAcceptsStablePublishedReleasesWithReadyWindowsAssets() throws {
        let valid = release()
        #expect(try GitHubReleaseClient.latest(in: GitHubReleaseClient.decode(JSONEncoder().encode([valid]), status: 200))?.tag_name == "v1.2.0")
        #expect(valid.page.absoluteString == "https://github.com/binbandit/riff/releases/tag/v1.2.0")
        let invalid = [
            GitHubRelease(tag_name: "v1.2.0", draft: true, prerelease: false, assets: valid.assets),
            GitHubRelease(tag_name: "v1.2.0", draft: false, prerelease: true, assets: valid.assets),
            release("v1.2.0-beta.1"),
            GitHubRelease(tag_name: "v1.2.0", draft: false, prerelease: false, assets: []),
            GitHubRelease(tag_name: "v1.2.0", draft: false, prerelease: false, assets: [.init(name: "Riff-win-x64.zip", state: "starter", size: 0)])
        ]
        for item in invalid {
            #expect(!item.isWindowsRelease)
            #expect(try GitHubReleaseClient.latest(in: [item]) == nil)
        }
        #expect(try GitHubReleaseClient.decode(Data(), status: 404).isEmpty)
        for code in [403, 429, 500] { #expect(throws: (any Error).self) { try GitHubReleaseClient.decode(Data(), status: code) } }
        #expect(throws: (any Error).self) { try GitHubReleaseClient.decode(Data("invalid".utf8), status: 200) }
    }
    @Test func findsVersionedCompanionAmongOtherReleasesAndChecksReadyAssets() throws {
        let companion = GitHubRelease(tag_name: "companion-v0.2.0", draft: false, prerelease: false, assets: [.init(name: "Riff-0.2.0-win-x64.zip", state: "uploaded", size: 100)])
        let ipad = GitHubRelease(tag_name: "v9.0.0", draft: false, prerelease: false, assets: [.init(name: "Riff-iPad-unsigned.ipa", state: "uploaded", size: 100)])
        #expect(companion.isWindowsRelease && companion.isNewer(than: "0.1.0"))
        #expect(companion.page.absoluteString == "https://github.com/binbandit/riff/releases/tag/companion-v0.2.0")
        #expect(try GitHubReleaseClient.latest(in: [ipad, companion, release("v0.1.0")])?.tag_name == companion.tag_name)
        let incomplete = GitHubRelease(tag_name: "companion-v0.3.0", draft: false, prerelease: false, assets: [])
        #expect(throws: (any Error).self) { try GitHubReleaseClient.latest(in: [companion, incomplete]) }
        let mismatch = GitHubRelease(tag_name: "companion-v0.3.0", draft: false, prerelease: false, assets: companion.assets)
        #expect(!mismatch.isWindowsRelease)
    }
    @Test func scansAllPagesBeforeChoosingVersionAndDoesNotTrustPartialFailures() async throws {
        var pages: [Int] = []
        let result = try await GitHubReleaseClient.fetchPages { page in
            pages.append(page)
            return page == 1 ? Array(repeating: release("v1.2.0"), count: 100) : [release("v1.10.0")]
        }
        #expect(pages == [1, 2] && result?.tag_name == "v1.10.0")
        do {
            _ = try await GitHubReleaseClient.fetchPages { page in
                if page == 2 { throw URLError(.notConnectedToInternet) }
                return Array(repeating: release(), count: 100)
            }
            Issue.record("Used an incomplete release list")
        } catch { #expect(error is URLError) }
    }
    @Test func boundedPaginationFailsClearlyInsteadOfClaimingCurrent() async {
        var requests = 0
        do {
            _ = try await GitHubReleaseClient.fetchPages { _ in requests += 1; return Array(repeating: release(), count: 100) }
            Issue.record("Claimed a partial release history was complete")
        } catch { #expect(error.localizedDescription.contains("too large")) }
        #expect(requests == 10)
    }
    @Test func githubRequestUsesPublicEndpointWithoutPairingCredentials() {
        let request = GitHubReleaseClient.request()
        #expect(request.url?.absoluteString == "https://api.github.com/repos/binbandit/riff/releases?per_page=100&page=1")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.httpBody == nil)
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "Riff-iPad")
        #expect(request.timeoutInterval == 10)
    }
    @Test func cachesAcrossLaunchesAndRefreshesAfterSixHours() async throws {
        let suite = "riff-updates-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var calls = 0
        let now = Date()
        let updates = CompanionUpdates(defaults: defaults) { calls += 1; return release() }
        await updates.check(now: now)
        await updates.check(now: now.addingTimeInterval(60))
        #expect(calls == 1)
        let reopened = CompanionUpdates(defaults: defaults) { calls += 1; return release("v1.3.0") }
        #expect(reopened.release?.tag_name == "v1.2.0")
        await reopened.check(now: now.addingTimeInterval(5 * 3600))
        #expect(calls == 1)
        await reopened.check(now: now.addingTimeInterval(6 * 3600))
        #expect(calls == 2 && reopened.release?.tag_name == "v1.3.0")
    }
    @Test func failedCheckKeepsLastKnownReleaseAndBacksOffButManualRetryWorks() async throws {
        let suite = "riff-updates-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var calls = 0
        let now = Date()
        let updates = CompanionUpdates(defaults: defaults) {
            calls += 1
            if calls == 2 { throw URLError(.notConnectedToInternet) }
            return calls == 1 ? release() : nil
        }
        await updates.check(now: now)
        await updates.check(now: now.addingTimeInterval(6 * 3600))
        #expect(updates.release?.tag_name == "v1.2.0" && updates.failure != nil)
        #expect(updates.checkedAt == now)
        await updates.check(now: now.addingTimeInterval(6 * 3600 + 60))
        #expect(calls == 2)
        await updates.check(force: true, now: now.addingTimeInterval(6 * 3600 + 61))
        #expect(calls == 3 && updates.failure == nil && updates.release == nil)
        await updates.check(now: now.addingTimeInterval(6 * 3600 + 120))
        #expect(calls == 3)
    }
    @Test func neverRunsConcurrentChecks() async throws {
        let suite = "riff-updates-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var resume: CheckedContinuation<GitHubRelease?, Never>?
        var calls = 0
        let updates = CompanionUpdates(defaults: defaults) {
            calls += 1
            return await withCheckedContinuation { resume = $0 }
        }
        let first = Task { await updates.check() }
        while resume == nil { await Task.yield() }
        await updates.check(force: true)
        #expect(calls == 1 && updates.checking)
        resume?.resume(returning: release())
        await first.value
        #expect(!updates.checking && updates.release?.tag_name == "v1.2.0")
    }
    @Test func oldSnapshotsStillDecodeAndNewVersionsRoundTrip() throws {
        let old = try JSONDecoder().decode(Snapshot.self, from: JSONEncoder().encode(Snapshot.starter))
        #expect(old.companionVersion == nil)
        var current = old; current.companionVersion = "1.2.3"
        #expect(try JSONDecoder().decode(Snapshot.self, from: JSONEncoder().encode(current)).companionVersion == "1.2.3")
    }
}
