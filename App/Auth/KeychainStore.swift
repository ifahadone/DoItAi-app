import Foundation
import Security

/// A minimal, typed wrapper over the iOS Keychain for storing auth tokens (AppSpec §13, ApiSpec §4.2
/// "tokens live in the iOS Keychain, never UserDefaults/App Group").
///
/// Stores generic-password items keyed by a string `account` under a single service. Values are
/// `Data`; convenience string helpers are provided. Items use
/// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` so tokens are readable by background sync after
/// the first unlock but never sync to iCloud or migrate to a new device (security priority).
///
/// Thread-safe: the Keychain API is itself thread-safe, and this type holds no mutable state.
/// Requires the Xcode app target (links `Security`); not part of the pure SPM packages.
struct KeychainStore: Sendable {
    /// Keychain service namespace. Defaults to the bundle id so multiple apps/extensions don't clash.
    let service: String
    /// Optional access group to share items between the app and its extensions. Set this to your
    /// `<TeamID>.<group>` when widgets need token access; leave nil for app-only.
    let accessGroup: String?

    init(service: String = AppConfig.bundleIdentifier, accessGroup: String? = nil) {
        self.service = service
        self.accessGroup = accessGroup
    }

    enum KeychainError: Error, Equatable {
        case unexpectedStatus(OSStatus)
        case dataConversionFailed
    }

    /// Well-known account keys for the tokens DoIT stores.
    enum Account {
        static let accessToken = "doit.accessToken"
        static let refreshToken = "doit.refreshToken"
        /// The Apple `sub` (stable user id) — handy for detecting account switches.
        static let appleUserId = "doit.appleUserId"
    }

    // MARK: Data API

    /// Insert or update the item for `account`.
    func set(_ value: Data, for account: String) throws {
        var query = baseQuery(account: account)

        // Try update first; if not found, add.
        let attributesToUpdate: [String: Any] = [kSecValueData as String: value]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)

        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            query[kSecValueData as String] = value
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.unexpectedStatus(addStatus) }
        default:
            throw KeychainError.unexpectedStatus(updateStatus)
        }
    }

    /// Read the item for `account`, or `nil` if absent.
    func data(for account: String) throws -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            return result as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Delete the item for `account` (no-op if absent).
    func remove(for account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Remove every item under this service (e.g. on logout-all).
    func removeAll() throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    // MARK: String convenience

    func set(_ string: String, for account: String) throws {
        guard let data = string.data(using: .utf8) else { throw KeychainError.dataConversionFailed }
        try set(data, for: account)
    }

    func string(for account: String) throws -> String? {
        guard let data = try data(for: account) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: Private

    private func baseQuery(account: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
        return query
    }
}
