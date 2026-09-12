import Foundation
import Testing
@testable import RiffProtocol

@MainActor struct AudioMonitoringTests {
    @Test(arguments: [true, false])
    func savesHeadphoneSettingsOnlyWhenTheCompanionSupportsThem(supported: Bool) async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let cache = folder.appendingPathComponent("snapshot.json")
        var snapshot = Snapshot.starter
        snapshot.capabilities = supported ? ["audio-monitor-v1"] : []
        snapshot.outputs = [AudioOutput(id: "cable", name: "CABLE Input"), AudioOutput(id: "headphones", name: "Headphones")]
        try JSONEncoder().encode(snapshot).write(to: cache)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/companion_state_server.py").path, cache.path]
        let pipe = Pipe(); process.standardOutput = pipe
        try process.run()
        defer { process.terminate(); process.waitUntilExit() }
        let pairing = try JSONDecoder().decode(Pairing.self, from: pipe.fileHandleForReading.availableData)
        let store = RiffStore(cacheURL: cache, pairing: pairing)
        await store.refresh()
        #expect(store.connected)
        #expect(store.supportsMonitoring == supported)
        try await store.audio(output: "cable", volume: 0.6, monitorEnabled: true, monitorOutput: "headphones", monitorVolume: 0.3)
        #expect(store.snapshot.outputId == "cable")
        #expect(store.snapshot.volume == 0.6)
        #expect(store.snapshot.monitorEnabled == (supported ? true : nil))
        #expect(store.snapshot.monitorOutputId == (supported ? "headphones" : nil))
        #expect(store.snapshot.monitorVolume == (supported ? 0.3 : nil))
        // A caller changing only the main output must preserve the saved headphone route.
        try await store.audio(output: "cable", volume: 0.2)
        let cached = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: cache))
        #expect(cached.volume == 0.2)
        #expect(cached.monitorVolume == (supported ? 0.3 : nil))
        #expect(cached.monitorEnabled == (supported ? true : nil))
    }
}
