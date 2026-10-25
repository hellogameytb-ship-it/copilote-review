/// copilote-render never touches the real Keychain: the settings it draws have no key.
enum KeychainStore {
    static func hasAPIKey() -> Bool { false }
    static func readAPIKey() -> String? { nil }
    static func saveAPIKey(_ key: String) -> Bool { false }
    static func deleteAPIKey() {}
}
