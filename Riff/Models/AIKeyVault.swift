import Foundation
import Security

@MainActor enum AIKeyVault {
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "Riff", kSecAttrAccount as String: "openai-api-key"]
    }
    static func load() -> String? {
        var query = query; query[kSecReturnData as String] = true
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func validated(_ value: String) throws -> String {
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (10...1024).contains(key.count), key.allSatisfy({ $0.isASCII && !$0.isWhitespace && !$0.isNewline && $0.asciiValue.map { $0 >= 33 && $0 <= 126 } == true }) else {
            throw RiffError.message("Paste a valid OpenAI API key.")
        }
        return key
    }
    static func save(_ value: String) throws -> String {
        let key = try validated(value)
        let data = Data(key.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query; insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else { throw RiffError.message("Could not save your API key securely.") }
        } else if status != errSecSuccess { throw RiffError.message("Could not update your API key securely.") }
        return key
    }
    static func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw RiffError.message("Could not remove your API key. Try again.") }
    }
}
