import Foundation
import Security

/// Minimal wrapper over the Keychain Services C API for storing small secrets
/// (here: the Traggo device token). We deliberately store *only* the token —
/// never the user's password.
///
/// Note: when running an unsigned dev build from the terminal, macOS may prompt
/// once to allow keychain access. A signed, bundled build won't.
enum Keychain {
    private static let service = "tools.primetime.PrimeTime"
    /// Pre-rename service identifier (#64). Items stored under it are migrated
    /// to `service` on first read and removed on write/delete, so tokens saved
    /// by older builds survive the rename without a re-login.
    private static let legacyService = "lol.stev.traggo-menu-app"

    static func set(_ value: String, account: String) {
        let base = baseQuery(service: service, account: account)
        // Upsert: delete any existing item, then add fresh.
        SecItemDelete(base as CFDictionary)
        var attributes = base
        attributes[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(attributes as CFDictionary, nil)
        // A fresh write supersedes any legacy copy; drop it so it can't
        // resurface later.
        SecItemDelete(baseQuery(service: legacyService, account: account) as CFDictionary)
    }

    static func get(account: String) -> String? {
        if let value = copy(service: service, account: account) {
            return value
        }
        // Miss under the current identifier: check the legacy one and migrate.
        guard let legacy = copy(service: legacyService, account: account) else {
            return nil
        }
        set(legacy, account: account)
        return legacy
    }

    static func delete(account: String) {
        SecItemDelete(baseQuery(service: service, account: account) as CFDictionary)
        SecItemDelete(baseQuery(service: legacyService, account: account) as CFDictionary)
    }

    private static func baseQuery(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private static func copy(service: String, account: String) -> String? {
        var query = baseQuery(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}
