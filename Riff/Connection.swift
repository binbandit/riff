import Foundation
import CryptoKit
import Security

struct Pairing: Codable, Sendable {
    let host: String
    let port: Int
    let token: String
    let fingerprint: String

    static func parse(_ text: String) throws -> Pairing {
        guard let parts = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              parts.scheme == "riff", parts.host == "connect" else {
            throw RiffError.message("Paste the full pairing link shown in Riff on your PC.")
        }
        func item(_ name: String) -> String? { parts.queryItems?.first(where: { $0.name == name })?.value }
        guard let host = item("host"), !host.isEmpty, host.count < 254,
              host.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") }),
              let portText = item("port"), let port = Int(portText), (1...65535).contains(port),
              let token = item("token"), token.count == 64, token.allSatisfy(\.isHexDigit),
              let fingerprint = item("fp"), fingerprint.count == 64, fingerprint.allSatisfy(\.isHexDigit) else {
            throw RiffError.message("This pairing link is incomplete. Copy it again from the Windows companion.")
        }
        return Pairing(host: host, port: port, token: token, fingerprint: fingerprint.lowercased())
    }
}
enum RiffError: LocalizedError {
    case message(String)
    var errorDescription: String? { switch self { case .message(let text): text } }
}

final class PinnedSessionDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let fingerprint: String
    init(fingerprint: String) { self.fingerprint = fingerprint }
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust,
              let certificates = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let leaf = certificates.first else {
            completionHandler(.cancelAuthenticationChallenge, nil); return
        }
        let digest = SHA256.hash(data: SecCertificateCopyData(leaf) as Data).map { String(format: "%02x", $0) }.joined()
        guard digest == fingerprint else { completionHandler(.cancelAuthenticationChallenge, nil); return }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

@MainActor final class CompanionClient {
    private struct Failure: Decodable { let error: String }
    let pairing: Pairing
    let session: URLSession
    init(pairing: Pairing) {
        self.pairing = pairing
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 70
        session = URLSession(configuration: config, delegate: PinnedSessionDelegate(fingerprint: pairing.fingerprint), delegateQueue: nil)
    }
    deinit { session.invalidateAndCancel() }
    func request<T: Decodable>(_ path: String, method: String = "GET", body: Data? = nil,
                                contentType: String = "application/json", as: T.Type = T.self) async throws -> T {
        var components = URLComponents()
        components.scheme = "https"; components.host = pairing.host; components.port = pairing.port
        components.percentEncodedPath = path.components(separatedBy: "?")[0]
        if path.contains("?") { components.percentEncodedQuery = path.components(separatedBy: "?").dropFirst().joined(separator: "?") }
        guard let url = components.url else { throw RiffError.message("The PC address is invalid.") }
        var request = URLRequest(url: url)
        request.httpMethod = method; request.httpBody = body
        if path == "/api/trigger" { request.timeoutInterval = 40 }
        if path == "/api/playback" { request.timeoutInterval = 2 }
        request.setValue("Bearer \(pairing.token)", forHTTPHeaderField: "Authorization")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw RiffError.message("The PC did not respond.") }
        guard (200..<300).contains(response.statusCode) else {
            let detail = (try? JSONDecoder().decode(Failure.self, from: data))?.error
            throw RiffError.message(detail ?? "The PC returned error \(response.statusCode).")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

@MainActor enum PairingVault {
    static let account = "riff-pairing"
    static func save(_ pairing: Pairing) throws {
        let data = try JSONEncoder().encode(pairing)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "Riff", kSecAttrAccount as String: account]
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else { throw RiffError.message("Could not save pairing securely.") }
        } else if status != errSecSuccess { throw RiffError.message("Could not update pairing securely.") }
    }
    static func load() -> Pairing? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "Riff", kSecAttrAccount as String: account, kSecReturnData as String: true]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(Pairing.self, from: data)
    }
    static func delete() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "Riff", kSecAttrAccount as String: account] as CFDictionary)
    }
}
