import Foundation
import Security

/// Manages secure storage of the backup password in the macOS Keychain.
final class KeychainManager {
    static let shared = KeychainManager()

    private let service = "com.makmak.MakLock"
    private let account = "backup-password"

    private init() {}

    /// Save a password to the Keychain.
    @discardableResult
    func savePassword(_ password: String) -> Bool {
        guard let data = password.data(using: .utf8) else { return false }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        // Try updating an existing item first; add if none exists
        let updateFields: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, updateFields as CFDictionary)
        if updateStatus == errSecSuccess {
            return true
        }

        // Item didn't exist (or we couldn't update it) — delete any stale entry and add fresh
        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        return addStatus == errSecSuccess
    }

    /// Verify a password against the stored Keychain entry.
    func verifyPassword(_ password: String) -> Bool {
        guard let stored = retrievePassword() else { return false }
        return stored == password
    }

    /// Check whether a backup password exists in the Keychain.
    /// Uses attribute-only query to avoid triggering the Keychain authorization dialog.
    func hasPassword() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return status == errSecSuccess
    }

    /// Remove the stored password from the Keychain.
    @discardableResult
    func deletePassword() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // MARK: - Private

    private func retrievePassword() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let password = String(data: data, encoding: .utf8) else {
            return nil
        }

        return password
    }
}
