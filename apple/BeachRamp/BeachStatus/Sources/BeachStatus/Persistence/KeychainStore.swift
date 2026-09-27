import Foundation
import Security

/// A minimal generic-password Keychain wrapper for the one secret the apps
/// hold: the chat key. Works unchanged on iOS and tvOS (tvOS has no iCloud
/// Keychain, so the key is entered once per Apple TV). Callers treat a
/// failed write as "keep it in memory for this session".
public enum KeychainStore {
    public static let service = "com.donwb.BeachRampTV.chat"

    public enum KeychainError: Error, Equatable {
        case unexpectedStatus(OSStatus)
        case encoding
    }

    public static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func write(_ value: String, account: String) throws {
        guard let data = value.data(using: .utf8) else { throw KeychainError.encoding }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let update = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if update == errSecSuccess { return }
        if update != errSecItemNotFound { throw KeychainError.unexpectedStatus(update) }

        var add = query
        attributes.forEach { add[$0.key] = $0.value }
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }

    public static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
