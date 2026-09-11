import Foundation
import Testing
@testable import RiffProtocol

@MainActor struct StoreTests {
    @Test func restoresAnExistingDeckWhenTheStarterWasDeleted() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let cache = folder.appendingPathComponent("snapshot.json")
        var state = Snapshot.starter
        state.decks.removeFirst()
        try JSONEncoder().encode(state).write(to: cache)
        let store = RiffStore(cacheURL: cache, pairing: nil)
        #expect(store.selectedDeck?.id == state.decks.first?.id)
        #expect(!store.connected)
        #expect(store.selectedDeck?.pads.count == 6)
    }

    @Test func uploadRefreshesBeforeReturningAndIgnoresAnOlderPoll() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let cache = folder.appendingPathComponent("snapshot.json")
        try JSONEncoder().encode(Snapshot.starter).write(to: cache)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/companion_state_server.py").path, cache.path]
        let pipe = Pipe(); process.standardOutput = pipe
        try process.run()
        defer { process.terminate(); process.waitUntilExit() }
        let pairing = try JSONDecoder().decode(Pairing.self, from: pipe.fileHandleForReading.availableData)
        let client = CompanionClient(pairing: pairing)
        let store = RiffStore(cacheURL: cache, pairing: pairing)
        await store.refresh()
        #expect(store.connected)
        let _: Acknowledgement = try await client.request("/test/hold-next-state")
        let stalePoll = Task { await store.refresh() }
        let started: Acknowledgement = try await client.request("/test/state-started")
        #expect(started.ok)
        let audio = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Shared/Sounds/nope.wav")
        let clip = try await store.upload(audio, name: "New sound")
        #expect(store.snapshot.clips.contains(where: { $0.id == clip.id }))
        #expect(store.snapshot.version == 1)
        let _: Acknowledgement = try await client.request("/test/release-state")
        await stalePoll.value
        #expect(store.snapshot.clips.contains(where: { $0.id == clip.id }))
        #expect(store.snapshot.version == 1)
        #expect(!store.busy)
        let cached = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: cache))
        #expect(cached.version == 1)

        // A failed follow-up poll must not turn a successful upload into a duplicate retry.
        let _: Acknowledgement = try await client.request("/test/fail-next-state")
        let saved = try await store.upload(audio, name: "Another sound")
        #expect(store.snapshot.clips.contains(where: { $0.id == saved.id }))
        #expect(!store.connected && !store.busy)
        #expect(store.connectionIssue?.contains("saved") == true)
        await store.refresh()
        #expect(store.connected && store.snapshot.version == 2)
        #expect(store.snapshot.clips.filter { $0.id == saved.id }.count == 1)
    }
}
