import Foundation
import Testing
@testable import RiffProtocol

@MainActor struct TransportTests {
    struct Reply: Decodable { let ok: Bool }

    @Test func pinnedTransportAcceptsOnlyThePairedCertificateAndNeverFollowsRedirects() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/https_server.py").path]
        let pipe = Pipe(); process.standardOutput = pipe
        try process.run()
        defer { process.terminate(); process.waitUntilExit() }
        let pairing = try JSONDecoder().decode(Pairing.self, from: pipe.fileHandleForReading.availableData)
        let client = CompanionClient(pairing: pairing)
        let reply: Reply = try await client.request("/ack")
        #expect(reply.ok)

        do {
            let _: Reply = try await client.request("/redirect")
            Issue.record("The client followed a redirect.")
        } catch { #expect(error.localizedDescription.contains("302")) }

        let invalidKey = CompanionClient(pairing: Pairing(host: pairing.host, port: pairing.port, token: String(repeating: "c", count: 64), fingerprint: pairing.fingerprint))
        do {
            let _: Reply = try await invalidKey.request("/ack")
            Issue.record("The server accepted an invalid access key.")
        } catch { #expect(error.localizedDescription == "Pairing expired.") }

        let impostor = CompanionClient(pairing: Pairing(host: pairing.host, port: pairing.port, token: pairing.token, fingerprint: String(repeating: "0", count: 64)))
        do {
            let _: Reply = try await impostor.request("/ack")
            Issue.record("The client accepted a different certificate.")
        } catch { #expect(error is URLError) }
    }
}
