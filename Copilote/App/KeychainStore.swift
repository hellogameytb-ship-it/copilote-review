import Foundation
import Security

/// The Anthropic API key lives only in the login Keychain, never on disk in clear.
enum KeychainStore {
    private static let service = "org.example.copilote"
    private static let account = "anthropic-api-key"

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    /// Checks presence without reading the secret (no Keychain access prompt).
    static func hasAPIKey() -> Bool {
        var query = baseQuery
        query[kSecReturnAttributes as String] = true
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    static func readAPIKey() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8), !key.isEmpty
        else { return nil }
        return key
    }

    @discardableResult
    static func saveAPIKey(_ key: String) -> Bool {
        let data = Data(key.utf8)
        let update = [kSecValueData as String: data] as CFDictionary
        let status = SecItemUpdate(baseQuery as CFDictionary, update)
        if status == errSecItemNotFound {
            var item = baseQuery
            item[kSecValueData as String] = data
            item[kSecAttrLabel as String] = "Copilote — API key Anthropic"
            return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
        }
        return status == errSecSuccess
    }

    static func deleteAPIKey() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
